# PIX via Pagou.ai — Guia operacional

Este documento descreve **como operar** a integração PIX no dia a dia. Para detalhes técnicos da implementação, ver `PAGOU_PIX_INTEGRATION_REPORT.md`.

## Configuração

### Variáveis de ambiente

```bash
PAGOU_API_KEY=                              # secret — apenas backend — chave de PRODUÇÃO
PAGOU_CONFIRMATION_MODE=webhook             # webhook (recomendado) | polling
PAGOU_WEBHOOK_SECRET=                       # só relevante em modo webhook
PUBLIC_APP_URL=https://app.exemplo.com      # só relevante em modo webhook
```

Definir no `.env` local e no painel do provedor de deploy. **Nunca commitar.**

> A Skill v3+ chama sempre `https://api.pagou.ai`. **Não há variável de ambiente para alterar isto.** `PAGOU_API_URL` é constante hardcoded no cliente HTTP.

### Como testar localmente sem cobranças reais

A Skill não tem sandbox. Para dev e CI sem tocar em produção, use o `tools/pagou-mock/` que vem no repo da Skill:

- Servidor Node (zero dependências, Node 20+) que simula a API v2 da Pagou
- Implementa as 4 rotas (`create`, `get`, `cancel`, `refund`)
- Dispara webhooks com HMAC válido
- Cenários por prefixo de `external_ref`: `expire-`, `refuse-`, `chargeback-`, `slow-`, `silent-`

Apontar o cliente HTTP do projeto para `http://localhost:8787` (ou porta configurada) durante dev/CI.

---

### Setup conforme `PAGOU_CONFIRMATION_MODE`

#### Se modo = `webhook` (recomendado)

1. Entrar no painel Pagou
2. Ir em Webhooks → Adicionar
3. URL: `{{PUBLIC_APP_URL}}/api/webhooks/pagou`
4. Selecionar eventos:
   - `transaction.created`
   - `transaction.pending`
   - `transaction.paid` ← **crítico**
   - `transaction.cancelled`
   - `transaction.refunded`
   - `transaction.chargedback`
5. Salvar — o painel devolve um **secret HMAC**
6. Colar o secret no `.env` como `PAGOU_WEBHOOK_SECRET=...`
7. Em produção, garantir que o secret está definido — sem ele a aplicação falha o boot (fail-closed)
8. Testar entrega — em dev, usar `tools/webhook-tester/` (HMAC válido contra localhost); em produção, fazer smoke test conforme `checklists/production.md`

#### Se modo = `polling`

> ⚠️ **AVISO — divergência com recomendação oficial da Pagou.** A doc oficial (`developer.pagou.ai`) afirma: *"Use GET polling only for reconciliation, support, or recovery, never as the primary flow."*
>
> Este modo usa GET como fluxo principal — caminho conscientemente diferente do recomendado. Aceitar a trade-off: latência maior (30s–1min), custo de API mais alto, e risco de perder eventos tardios (refunded, chargedback) se o job de reconciliação falhar. Adequado para MVP / volume baixo / sem URL pública. Para integrações de produção sérias, **considera migrar para `webhook`** — o endpoint já está gerado pela Skill, só precisas de registar no painel.

Sem painel. Sem secret. A confirmação acontece via:

1. **Background poller** (`pagou:poll`) que corre a cada minuto, consulta `GET /v2/transactions/{id}` para todas as transações pending na última hora, e propaga status terminais (`paid`, `expired`, `canceled`, `refused`) ao pedido interno.
2. **Job de reconciliação** (`pagou:reconcile-late`) que corre a cada 15 min, consulta transações já terminais nos últimos 30 dias, e propaga estados pós-pagamento (`refunded`, `partially_refunded`, `chargedback`).

Verificar que ambos os jobs estão agendados:

| Stack | Como verificar |
|---|---|
| Next.js | `vercel.json` → secção `crons` lista 2 entradas |
| Laravel | `php artisan schedule:list` mostra `pagou:poll` e `pagou:reconcile-late` |
| WordPress | `wp cron event list` mostra `pagou_pix_poll` e `pagou_pix_reconcile_late` |
| Outros | conforme scheduler do stack |

**Limitações conhecidas em modo polling:**

- Latência de confirmação ≈ 30s–1 min (depende da granularidade do scheduler).
- Custo de API maior — N transações pending × frequência de polling.
- Se o job de reconciliação tardia não correr durante mais de 30 dias, perdes refund/chargeback.
- Se houver volume alto ou janela operacional crítica, considerar migrar para modo `webhook`.

## Fluxo de pagamento

**Passos 1–7 são iguais em ambos os modos.** Os passos 8+ diferem conforme `PAGOU_CONFIRMATION_MODE`.

```
1.  Cliente clica "Pagar com PIX" no checkout
2.  Frontend chama POST {{/api/pagou/pix}} com { orderId }
3.  Backend chama POST /v2/transactions na Pagou
4.  Backend persiste em pagou_pix_transactions
5.  Backend retorna { pix_qr_code, pix_code, transaction_id, status: "pending" }
6.  Frontend renderiza QR + copia-e-cola
7.  Cliente paga pelo app do banco
```

### Se modo = `webhook`

```
8.  Pagou envia POST {{/api/webhooks/pagou}} com transaction.paid (segundos depois)
9.  Backend valida HMAC + dedup por event.id + enfileira job
10. Job atualiza pagou_pix_transactions e marca order como pago
11. Frontend polling interno /api/orders/{id}/status detecta "pago"
12. UX confirma sucesso ao cliente
```

### Se modo = `polling`

```
8.  Cliente continua na página (ou fecha — não importa!)
9.  Background poller (corre cada 1 min) consulta GET /v2/transactions/{id}
10. Detecta status="paid" → atualiza pagou_pix_transactions → marca order como pago
11. Frontend polling interno /api/orders/{id}/status detecta "pago" (≈ 30-60s após pagar)
12. UX confirma sucesso ao cliente

— Mais tarde —

13. Cliente pede refund / faz chargeback
14. Job de reconciliação (cada 15 min) detecta novo status terminal
15. Order é actualizada para refunded/chargeback
```

**Em ambos os modos, a confirmação NUNCA vem do retorno síncrono do POST inicial nem de polling do frontend à API Pagou.**

## Endpoints

### `POST {{/api/pagou/pix}}`

Auth: sessão do usuário

Request:
```json
{ "order_id": "ord_1001" }
```

Response 200:
```json
{
  "transaction_id": "tr_1001",
  "status": "pending",
  "pix_qr_code": "<base64 string>",
  "pix_code": "<BR Code copia e cola>"
}
```

### `POST {{/api/webhooks/pagou}}`

Auth: pública (Pagou chama)

Response sempre:
```json
{ "received": true }
```

### `POST {{/admin/pagou/reconcile/:transaction_id}}`

Auth: admin

Força reconciliação via `GET /v2/transactions/:id` na Pagou e atualiza o pedido se necessário.

## Tabelas

### `pagou_pix_transactions`
Uma linha por cobrança PIX criada. UNIQUE em `external_ref` (= `order_id`) e em `pagou_transaction_id`.

### `pagou_webhook_events`
Uma linha por evento recebido. UNIQUE em `event_id` — **fonte de idempotência**.

## Operação

### Verificar saúde

```sql
-- Eventos não processados há mais de 5 minutos
SELECT * FROM pagou_webhook_events
WHERE processed_at IS NULL
  AND created_at < NOW() - INTERVAL '5 minutes';

-- Transações pendentes há mais de 1 hora
SELECT * FROM pagou_pix_transactions
WHERE status = 'pending'
  AND created_at < NOW() - INTERVAL '1 hour';
```

### Reconciliar manualmente

```bash
curl -X POST {{PUBLIC_APP_URL}}/admin/pagou/reconcile/tr_1001 \
  -H "Authorization: Bearer <admin_token>"
```

### Reconciliação noturna (cron)

{{Descrever como está agendado: Vercel cron / Laravel schedule / wp-cron / etc.}}

### Logs

Buscar por:
- `event=pagou.pix.create` — criações
- `event=pagou.webhook.received` — webhooks
- `event=pagou.webhook.duplicate` — duplicatas detectadas (esperado)
- `event=pagou.webhook.error` — erros no processamento (investigar)
- `event=pagou.reconcile.result` — reconciliações

### Alertas recomendados

| Métrica | Condição | Ação |
|---|---|---|
| `pagou.webhook.error` | > 0 em 5 min | Investigar log |
| `pagou.webhook.received` | = 0 em 24h em produção | Webhook quebrado |
| `pagou.pix.create` p95 | > 3s | API Pagou lenta — verificar status page |
| `pagou_pix_transactions` em `pending` > 24h | > 0 | Job de reconciliação ou tracking quebrado |

## Status PIX e o que significam

| Pagou | Status interno | Significa |
|---|---|---|
| `pending` | `{{aguardando_pagamento}}` | QR gerado, aguardando o cliente |
| `paid` | `{{pago}}` | **Liberar produto/acesso** |
| `expired` | `{{expirado}}` | Cliente não pagou a tempo |
| `canceled` | `{{cancelado}}` | Cancelado antes do pagamento |
| `refused` | `{{recusado}}` | Banco recusou |
| `refunded` | `{{estornado}}` | Estorno total |
| `partially_refunded` | `{{estornado_parcial}}` | Estorno parcial |
| `chargedback` | `{{chargeback}}` | Disputa — agir |

## Troubleshooting

### "Cliente diz que pagou mas o pedido não foi liberado"

1. Buscar `pagou_pix_transactions` por `order_id`
2. Reconciliar: `POST {{/admin/pagou/reconcile/<transaction_id>}}`
3. Se Pagou retornar `paid` e nosso registro estava `pending` → webhook foi perdido. Reconciliação corrigiu.
4. Investigar: ver se `pagou_webhook_events` tem evento com aquele `resource_id` (`data.id`).

### "Recebi webhook 2 vezes"

Verificar `pagou_webhook_events` — só deve haver 1 linha por `event_id`. A constraint UNIQUE garante isso.

### "Webhook tomando timeout"

O handler deve responder em < 5s. Se está demorando:
1. Verificar se o processamento pesado está dentro do handler (errado) ou na fila (correto)
2. Mover para fila se necessário

### "PAGOU_API_KEY inválida"

- Confirmar que `PAGOU_API_KEY` é a chave correta da conta produção (não há sandbox na Skill v3+)
- Confirmar que a variável está setada no servidor (não apenas no `.env` local)

## Limites e considerações

- Pagou v2 trabalha em **centavos** — ao integrar com outros sistemas, converter
- `external_ref` máximo 128 chars
- Webhook deve responder em < 5s — sempre processar lógica async
- API key é segredo — **nunca** no frontend, **nunca** em commits

## Referências

- Docs Pagou: https://developer.pagou.ai
- OpenAPI v2: https://developer.pagou.ai/api-reference/openapi-v2.json
- SDK TS: `@pagouai/api-sdk`
- Relatório técnico: `PAGOU_PIX_INTEGRATION_REPORT.md`
- Score: `PAGOU_PIX_INTEGRATION_SCORE.md`
