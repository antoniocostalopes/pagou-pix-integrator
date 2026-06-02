# KNOWLEDGE.md — Verdade sobre a API Pagou.ai

Esta é a **única fonte de verdade** desta Skill sobre a API Pagou. Antes de gerar código que toca na API, releia o trecho relevante. Se algo não está aqui ou na OpenAPI oficial, **não invente**.

## Documentação oficial

| Recurso | URL |
|---|---|
| Docs rápidas (LLMs) | https://developer.pagou.ai/llms.txt |
| Docs completas (LLMs) | https://developer.pagou.ai/llms-full.txt |
| OpenAPI v2 (JSON) | https://developer.pagou.ai/api-reference/openapi-v2.json |
| Sandbox | https://api-sandbox.pagou.ai |
| Produção | https://api.pagou.ai |

## Autenticação

Três métodos suportados — **escolha um** e mantenha consistente:

```http
Authorization: Bearer <PAGOU_API_KEY>
```

```http
apiKey: <PAGOU_API_KEY>
```

```http
Authorization: Basic base64(<PAGOU_API_KEY>:x)
```

**Recomendação desta Skill:** `Authorization: Bearer` — é o padrão moderno e o mais previsível para middlewares.

**Regras absolutas:**

- Chave secreta apenas no servidor (`process.env`, env vars do sistema, secret manager)
- Nunca no bundle do frontend
- Nunca em commits (.env no .gitignore)
- Nunca em logs (mascarar antes de logar)

## Regras de ouro da API v2

1. **Valores em centavos** — R$ 15,00 = `1500`
2. **`external_ref` obrigatório** em todas as escritas — usar id interno do pedido (`order_1001`)
3. **Idempotência** garantida pelo `external_ref` quando combinado com a lógica de "criar ou recuperar"
4. **Webhooks são a fonte da verdade** — polling com GET só para reconciliação/recuperação/suporte
5. **Cards** exigem Payment Element (SDK v3) — backend só recebe tokens `pgct_`
6. **Não inventar** endpoints, campos ou status fora da OpenAPI

## Criar cobrança PIX

```
POST /v2/transactions
Content-Type: application/json
Authorization: Bearer <PAGOU_API_KEY>
```

```json
{
  "external_ref": "order_1001",
  "amount": 1500,
  "currency": "BRL",
  "method": "pix",
  "buyer": {
    "name": "Customer Name",
    "email": "customer@example.com",
    "document": { "type": "CPF", "number": "12345678901" }
  }
}
```

**Resposta** (campos essenciais):

- `id` — id da transação (ex.: `tr_1001`)
- `status` — `pending` ao criar
- `pix_qr_code` — string base64 do QR Code (renderizar como imagem)
- `pix_code` — string "copia e cola" (BR Code / EMV)
- `external_ref` — eco do enviado
- `correlation_id` — útil para tracing

## Consultar transação (reconciliação)

```
GET /v2/transactions/{id}
```

Use **apenas** para:

- Recuperar estado após erro/timeout
- Diagnóstico de suporte
- Job de reconciliação noturna

Nunca como fluxo principal.

## Status da transação

```
pending → paid
        → expired
        → canceled
        → refused
        → refunded
        → partially_refunded
        → chargedback
```

### Mapeamento sugerido (status interno do projeto)

| Pagou | Sugestão de status interno | Significado |
|---|---|---|
| `pending` | `aguardando_pagamento` | QR gerado, ainda não pago |
| `paid` | `pago` | **Liberar acesso/entregar produto** |
| `expired` | `expirado` | Tempo do QR esgotou |
| `canceled` | `cancelado` | Cancelado antes do pagamento |
| `refused` | `recusado` | Banco recusou |
| `refunded` | `estornado` | Devolvido após pagamento |
| `partially_refunded` | `estornado_parcial` | Devolução parcial |
| `chargedback` | `chargeback` | Disputa do pagador |

O mapeamento real depende do domínio do projeto (perguntar ao usuário se houver dúvida).

## Webhooks — estrutura de evento de transação

```json
{
  "id": "evt_pay_1001",
  "event": "transaction",
  "data": {
    "event_type": "transaction.paid",
    "id": "tr_1001",
    "status": "paid",
    "correlation_id": "order_1001"
  }
}
```

### ⚠️ Crítico — Deduplicação

| Campo | É id de quê | Usar para dedupe? |
|---|---|---|
| `id` (topo) | **Evento** | ✅ **SIM** — único por entrega |
| `data.id` | Transação | ❌ NÃO — uma transação emite múltiplos eventos |
| `data.correlation_id` | Pedido externo (`external_ref`) | ❌ NÃO — agrega N transações |

**Regra desta Skill (vinda do PRD):** dedupe sempre por `event.id` (top-level). Persistir numa tabela `pagou_webhook_events` com `event_id` UNIQUE.

### Eventos de transação (todos)

- `transaction.created`
- `transaction.pending`
- `transaction.paid` ← libera entrega
- `transaction.cancelled`
- `transaction.refunded`
- `transaction.chargedback`
- `transaction.three_ds_required` ← cartão; ignorar em fluxo só-PIX

### Roteamento

- Pagamentos: `event === "transaction"` → ler `data.event_type`
- Subscriptions: `event === "subscription"` → ler `data.event_type`
- Transfers (payout): top-level `type` (sem campo `event`)

### Resposta do webhook

Responder **rápido** com 200 e corpo:

```json
{ "received": true }
```

Processar lógica pesada **depois** — preferencialmente assíncrono (fila, job, background task). Se síncrono, manter abaixo de 5 segundos.

## Erros comuns que esta Skill rejeita

| Erro | Correção |
|---|---|
| Retry de POST quando der erro | Reconciliar com GET, não retentar POST |
| Dedup por `data.id` | Dedup por `id` de topo (event id) |
| Esquecer `external_ref` | Sempre incluir — sem isto, reconciliação fica impossível |
| Tratar número de cartão cru | Usar Payment Element (fora do escopo PIX, mas para o caso) |
| Confiar no sucesso do browser | Estado final só via webhook ou GET reconciliado |
| Ignorar `next_action` em 3DS | Fora do escopo PIX |
| Valores em reais | Sempre converter para centavos (× 100) |

## Tabelas de DB sugeridas

### `pagou_pix_transactions`

| Coluna | Tipo | Observação |
|---|---|---|
| `id` | PK do banco | |
| `pagou_transaction_id` | string, UNIQUE | id retornado pela Pagou (`tr_...`) |
| `external_ref` | string, UNIQUE | id interno do pedido |
| `order_id` (FK) | depende do schema | liga ao pedido do projeto |
| `amount_cents` | integer | em centavos |
| `currency` | string(3) | `BRL` |
| `status` | string | status Pagou cru |
| `pix_qr_code` | text | base64 |
| `pix_code` | text | BR Code |
| `raw_response` | json | resposta crua da Pagou |
| `created_at` | timestamp | |
| `updated_at` | timestamp | |

### `pagou_webhook_events`

| Coluna | Tipo | Observação |
|---|---|---|
| `id` | PK do banco | |
| `event_id` | string, **UNIQUE** | `event.id` de topo — base da dedup |
| `event_type` | string | `transaction.paid`, etc. |
| `resource_id` | string | `data.id` (id da transação) |
| `correlation_id` | string | `data.correlation_id` |
| `payload` | json | corpo cru recebido |
| `processed_at` | timestamp | nulo até processar |
| `created_at` | timestamp | |

A constraint UNIQUE em `event_id` é o que garante idempotência: o INSERT falha silenciosamente em dupla entrega.

## SDK TypeScript oficial

```bash
npm i @pagouai/api-sdk
# ou
bun add @pagouai/api-sdk
# ou
pnpm add @pagouai/api-sdk
```

```ts
import { Client } from "@pagouai/api-sdk";

const client = new Client({
  apiKey: process.env.PAGOU_API_KEY!,
  environment: process.env.PAGOU_ENV === "production" ? "production" : "sandbox",
});

const tx = await client.transactions.create({
  external_ref: "order_1001",
  amount: 1500,
  currency: "BRL",
  method: "pix",
});
```

Use o SDK quando o projeto for Node/TS. Para outras linguagens, faça wrapper HTTP simples.

## Fora do escopo desta Skill (mas documentado para contexto)

### Subscriptions (recorrência)

`POST /v2/subscriptions` — exige token de cartão (`pgct_`) vindo do Payment Element. Status: `trialing → active | past_due | cancel_scheduled | canceled`. Eventos: `subscription.created`, `subscription.renewed`, `subscription.canceled`, etc.

### Transfers (Pix Out / payout)

`POST /v2/transfers` — envia dinheiro para uma chave PIX. Status: `pending → in_analysis → processing → paid | error | cancelled`. Estrutura de webhook diferente: top-level `type`, e `data.object.id`.

Se o usuário pedir explicitamente para incluir, abra escopo e siga a mesma disciplina (dedup por event id de topo, status mapping, testes, etc.).
