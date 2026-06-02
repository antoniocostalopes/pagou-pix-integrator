# PIX via Pagou.ai — Guia operacional

Este documento descreve **como operar** a integração PIX no dia a dia. Para detalhes técnicos da implementação, ver `PAGOU_PIX_INTEGRATION_REPORT.md`.

## Configuração

### Variáveis de ambiente

```bash
PAGOU_API_KEY=                              # secret — apenas backend
PAGOU_ENV=sandbox                           # sandbox | production
PAGOU_BASE_URL=                             # opcional; default por ambiente
PUBLIC_APP_URL=https://app.exemplo.com      # URL pública do projeto
```

Definir no `.env` local e no painel do provedor de deploy. **Nunca commitar.**

### Base URLs

| `PAGOU_ENV` | URL |
|---|---|
| `sandbox` | `https://api-sandbox.pagou.ai` |
| `production` | `https://api.pagou.ai` |

### Registrar webhook na Pagou

1. Entrar no painel Pagou ({{link específico}})
2. Ir em Webhooks → Adicionar
3. URL: `{{PUBLIC_APP_URL}}/api/webhooks/pagou`
4. Selecionar eventos:
   - `transaction.created`
   - `transaction.pending`
   - `transaction.paid` ← **crítico**
   - `transaction.cancelled`
   - `transaction.refunded`
   - `transaction.chargedback`
5. Salvar e testar entrega

## Fluxo de pagamento

```
1. Cliente clica "Pagar com PIX" no checkout
2. Frontend chama POST {{/api/pagou/pix}} com { orderId }
3. Backend chama POST /v2/transactions na Pagou
4. Backend persiste em pagou_pix_transactions
5. Backend retorna { pix_qr_code, pix_code, transaction_id, status: "pending" }
6. Frontend renderiza QR + copia-e-cola
7. Cliente paga pelo app do banco
8. Pagou envia POST {{/api/webhooks/pagou}} com transaction.paid
9. Backend valida + dedup + enfileira job
10. Job atualiza pagou_pix_transactions e marca order como pago
11. Frontend faz polling do status do pedido (ou usa SSE/websocket) — encontra "pago"
12. UX confirma sucesso ao cliente
```

**A confirmação do pagamento sempre vem do webhook, nunca do sucesso do POST inicial.**

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

- Confirmar que `PAGOU_ENV` corresponde à chave (sandbox key não funciona em prod)
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
