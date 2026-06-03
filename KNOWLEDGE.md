# KNOWLEDGE.md — Verdade sobre a API Pagou.ai

Esta é a **única fonte de verdade** desta Skill sobre a API Pagou. Antes de gerar código que toca na API, releia o trecho relevante. Se algo não está aqui ou na OpenAPI oficial, **não invente**.

## Documentação oficial

| Recurso | URL |
|---|---|
| Docs rápidas (LLMs) | https://developer.pagou.ai/llms.txt |
| Docs completas (LLMs) | https://developer.pagou.ai/llms-full.txt |
| OpenAPI v2 (JSON) | https://developer.pagou.ai/api-reference/openapi-v2.json |
| Produção (única URL usada pela Skill v3+) | https://api.pagou.ai |

> **A Skill v3.0.0+ só fala com produção.** Não há sandbox configurável. Para dev/CI local sem cobranças reais, usar `tools/pagou-mock/` incluído no repo da Skill (servidor Node que simula a API v2 com webhooks HMAC válidos).

## Tracing — `requestId`

A Pagou devolve um header de identificação de pedido na resposta de cada chamada — útil para troubleshooting e correlação com logs do suporte oficial.

**Header a procurar:** `x-request-id` ou `x-pagou-request-id` (qual estiver disponível na resposta).

**Regras:**

- Logar o `requestId` em toda chamada bem ou mal sucedida (`event: "pagou.api.call"` + `status` + `requestId`).
- Propagar o `requestId` na exceção do cliente HTTP (`PagouError.requestId` em TS, `PagouException::$requestId` em PHP) — facilita escalar incidentes para o suporte.
- **Não** logar payload nem chave de API junto com o requestId — só metadados (path, status, requestId).
- Cobertura: incluir no checklist `validation.md` que toda chamada HTTP loga requestId quando devolvido.

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
4. **Webhooks são o padrão recomendado** — `GET /v2/transactions/{id}` é o caminho alternativo quando o utilizador escolhe `PAGOU_CONFIRMATION_MODE=polling` (sem URL pública / sem registo no painel). Em qualquer dos modos, **nunca** confirmar pagamento a partir do retorno síncrono do POST de criação ou de polling do browser à API Pagou
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

## Cancelar transação PIX (PIX ainda pendente)

```
POST /v2/transactions/{id}/cancel
Authorization: Bearer <PAGOU_API_KEY>
```

Cancela uma cobrança PIX que ainda **não foi paga**. Após cancelar, o cliente que tentar pagar o QR vai receber erro no banco.

**Resposta esperada:** transação com `status: "canceled"` + eventual emissão de webhook `transaction.cancelled`.

**Quando usar:**

- Cliente desistiu do checkout
- Pedido foi cancelado por outro motivo (stock, fraude detetada, etc.)
- Pedido foi reaberto e criou-se nova cobrança (cancela a anterior)

**Pré-condições:**

- Status atual = `pending` — não funciona em `paid`/`expired`/`canceled`
- Tentar cancelar em estado inválido → 4xx (tratar como no-op)

## Estornar transação PIX (reverter pagamento)

```
POST /v2/transactions/{id}/refund
Authorization: Bearer <PAGOU_API_KEY>
Content-Type: application/json
```

```json
{
  "amount": 1500,
  "reason": "Customer requested refund"
}
```

- `amount` — em centavos. Se omitido ou igual ao total, estorno **total**. Se menor, **parcial** (cuidado: alguns provedores não permitem múltiplos parciais).
- `reason` — opcional mas recomendado para auditoria.

**Resposta esperada:** estorno registado + webhook `transaction.refunded` (ou `transaction.partially_refunded` em parcial) chega em breve.

**Quando usar:**

- Cliente pediu reembolso
- Produto/serviço não pôde ser entregue
- Decisão comercial (devolução de cortesia, ajuste de valor)

**Pré-condições:**

- Status atual = `paid` ou `partially_refunded` (para múltiplos parciais)
- Janela de 90-180 dias após pagamento (verificar limites Pagou/Banco Central)

> ⚠️ **Mesmo após chamar refund, espere o webhook** `transaction.refunded` para atualizar status interno. A chamada POST inicia o processo; o estorno bancário pode levar minutos a horas.

## Consultar transação (polling ou reconciliação)

```
GET /v2/transactions/{id}
```

**Em modo `webhook` (default da Skill):** use **apenas** para reconciliação — recuperar estado após erro/timeout, diagnóstico de suporte, job de reconciliação periódico. Nunca como fluxo principal de confirmação.

**Em modo `polling` (opt-out da Skill):** este endpoint **é** o fluxo principal de confirmação. Background poller no servidor pergunta a cada 30s desde a criação do PIX até estado terminal (`paid`, `expired`, `canceled`, `refused`) ou até `expiration` do PIX expirar. Frontend nunca chama directamente — pergunta a um endpoint interno (`/api/orders/:id/status`) que reflecte o estado já actualizado pelo poller.

**Limitações conhecidas do modo polling** (a Skill documenta no `PAGOU_PIX_INTEGRATION_REPORT.md`):

- Eventos tardios pós-terminal (`refunded`, `partially_refunded`, `chargedback`) só são apanhados pelo job de reconciliação periódico (que continua a pergunta para transações até 30 dias após criação). Risco real: se o job não correr ou tiver janela curta, perdes a notificação.
- Latência de confirmação ≈ intervalo de polling (30s por defeito). UX "pago" demora segundos a aparecer.
- Custo de API: N pedidos × (TTL / 30s) requests ao endpoint GET. Para 1000 PIX/dia com TTL 1h, ≈ 120 mil requests/dia.

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

### Verificação de assinatura HMAC do webhook

A Pagou pode enviar uma **assinatura HMAC-SHA256** num header dedicado para confirmar autenticidade (consultar OpenAPI/painel mais recente para confirmar disponibilidade):

```
X-Pagou-Signature: <hex digest>
```

Cálculo no teu lado:

```
expected = HMAC-SHA256(raw_request_body, PAGOU_WEBHOOK_SECRET)
ok       = constant_time_compare(expected, header)
```

**Regras críticas:**

1. **Usar o body cru** — antes de qualquer parse JSON. Se reformatares, o hash muda.
2. **Comparação em tempo constante** (`timingSafeEqual` em Node, `hash_equals` em PHP, `secrets.compare_digest` em Python). `==` vaza timing.
3. **Falhar fechado** — assinatura inválida → `401`, não persiste o evento.
4. **Fallback seguro em dev** — se `PAGOU_WEBHOOK_SECRET` não estiver definido, logar warning e permitir (não bloquear dev local). **Em produção** (detectada pelo runtime do framework: `NODE_ENV=production`, `APP_ENV=production`, etc. — não há `PAGOU_ENV` na Skill v3+) e com secret ausente → sair com erro no boot.

**Env var nova:**

```bash
PAGOU_WEBHOOK_SECRET=               # secret HMAC obtido no painel Pagou ao registar o webhook
```

> Se a versão da API que estás a usar **não** suporta HMAC, deixar a verificação como placeholder configurável e mover para defesa por **allowlist de IP** se a Pagou publicar range. Documentar a decisão em `PAGOU_PIX_INTEGRATION_REPORT.md`.

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
  // Skill v3+: SDK aponta SEMPRE para produção.
  // O SDK aceita "sandbox" mas a Skill não suporta esse modo — para dev/CI sem cobranças reais,
  // ver `tools/pagou-mock/` no repo da Skill (servidor Node que simula a API v2).
  environment: "production",
});

const tx = await client.transactions.create({
  external_ref: "order_1001",
  amount: 1500,
  currency: "BRL",
  method: "pix",
});
```

⚠️ **Atenção ao copiar snippets da documentação oficial da Pagou.** Os exemplos em `https://developer.pagou.ai` podem mostrar `environment: "sandbox"`. **Na Skill v3+, sempre substituir por `"production"`.** Se precisas de testar sem cobranças reais, aponta o SDK para `tools/pagou-mock/` localmente (via base URL override do SDK, se disponível) ou usa o wrapper HTTP customizado dos adapters da Skill, que tem a URL hardcoded.

Use o SDK quando o projeto for Node/TS. Para outras linguagens, faça wrapper HTTP simples.

## Fora do escopo desta Skill (mas documentado para contexto)

### Subscriptions (recorrência)

`POST /v2/subscriptions` — exige token de cartão (`pgct_`) vindo do Payment Element. Status: `trialing → active | past_due | cancel_scheduled | canceled`.

**Estrutura do evento de webhook:**

```json
{
  "id": "evt_sub_1001",
  "event": "subscription",
  "data": {
    "event_type": "subscription.created",
    "id": "sub_1001",
    "status": "active",
    "customer_email": "customer@example.com"
  }
}
```

**9 eventos possíveis** (roteamento: `event === "subscription"` → ler `data.event_type`):

| Evento | Significado | Ação típica |
|---|---|---|
| `subscription.created` | Assinatura criada | Activar conta / role |
| `subscription.started` | Período de trial terminou, cobrança real começou | Confirmar acesso pago |
| `subscription.renewed` | Cobrança recorrente bem sucedida | Estender prazo de acesso |
| `subscription.updated` | Algo mudou (preço, intervalo, payment method) | Atualizar localmente |
| `subscription.canceled` | Cancelamento confirmado | Revogar acesso ao fim do período pago |
| `subscription.payment_failed` | Cobrança falhou | Notificar utilizador, marcar grace period |
| `subscription.past_due` | Cobrança em atraso depois do grace period | Suspender acesso |
| `subscription.trial_will_end` | Trial termina em breve | Notificar utilizador |
| `subscription.chargeback_received` | Disputa do pagador | Revogar acesso + alertar fraud team |

### Transfers (Pix Out / payout)

`POST /v2/transfers` — envia dinheiro para uma chave PIX. Status: `pending → in_analysis → processing → paid | error | cancelled`.

**⚠️ Estrutura do evento de webhook é DIFERENTE** dos outros dois produtos — top-level `type` (não `event`), e `data.object.id` (não `data.id`):

```json
{
  "id": "evt_payout_1001",
  "type": "payout.transferred",
  "data": {
    "object": {
      "id": "po_1001",
      "status": "paid"
    }
  }
}
```

**6 eventos possíveis** (roteamento: ler `type` no topo, não `event` — distingue de transaction/subscription):

| Evento | Significado |
|---|---|
| `payout.created` | Transferência criada |
| `payout.in_analysis` | Em análise antifraude |
| `payout.processing` | Em processamento bancário |
| `payout.transferred` | **Transferência concluída** com sucesso |
| `payout.failed` | Falhou (motivo em `data.object.failure_reason` se presente) |
| `payout.canceled` | Cancelada antes de concluir |

### Roteamento defensivo do webhook handler

Mesmo sendo a Skill PIX-only, o endpoint `/api/webhooks/pagou` deve **não falhar** se a Pagou enviar eventos de subscription/transfer (porque outros produtos da Pagou podem partilhar a URL no painel do utilizador). Padrão recomendado:

```pseudo
function handleWebhook(body):
    # Já fizemos dedup por id top-level
    if body.event == "transaction":
        # Caminho principal da Skill — processar normalmente
        return processPaymentEvent(body)

    if body.event == "subscription":
        # Fora do escopo da Skill, mas não rejeitar
        log_info("subscription event ignored — out of skill scope", evt=body.id, type=body.data.event_type)
        return { received: true }

    if body.type and body.type.startswith("payout."):
        # Transfer — estrutura diferente, fora do escopo
        log_info("payout event ignored — out of skill scope", evt=body.id, type=body.type)
        return { received: true }

    # Evento desconhecido — não falhar, mas logar para investigação
    log_warn("unknown webhook event shape", evt=body.id)
    return { received: true }
```

Esta defensiva está implementada nos adapters quando o utilizador escolhe modo `webhook`. **Não** implementa a lógica de subscription/transfer — só evita que a Pagou receba 5xx e fique a tentar reenviar.

Se o utilizador pedir explicitamente para implementar subscription ou transfer, **rejeitar** com mensagem amigável: *"A Skill `pagou-pix-integrator` é PIX-only por design. Para subscription/transfer, ver a documentação oficial em https://developer.pagou.ai."* (decisão permanente — ver `SKILL.md` secção "Fora do escopo").
