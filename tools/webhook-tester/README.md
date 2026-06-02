# Webhook Tester

Envia eventos de webhook **simulados** para o teu endpoint local, com assinatura HMAC válida. Útil para:

- Testar o handler de webhook sem precisar correr o mock server inteiro
- Validar dedup (enviar duas vezes o mesmo `event.id`)
- Simular eventos raros (`chargedback`, `expired`, fora de ordem)

## Uso rápido

```bash
# Envia transaction.paid para http://localhost:3000/api/webhooks/pagou
bash tools/webhook-tester/send.sh paid

# Envia evento específico
bash tools/webhook-tester/send.sh chargedback

# Envia para URL customizada
WEBHOOK_URL=http://localhost:8080/webhooks/pagou bash tools/webhook-tester/send.sh paid

# Com secret customizado
WEBHOOK_SECRET=meu-secret bash tools/webhook-tester/send.sh paid
```

## Variáveis de ambiente

| Var | Default |
|---|---|
| `WEBHOOK_URL` | `http://localhost:3000/api/webhooks/pagou` |
| `WEBHOOK_SECRET` | `dev-secret-please-change` |
| `EXTERNAL_REF` | `order_test_1001` |
| `TRANSACTION_ID` | `tr_test_1001` |

## Eventos disponíveis

| Argumento | Evento enviado |
|---|---|
| `created` | `transaction.created` |
| `pending` | `transaction.pending` |
| `paid` | `transaction.paid` |
| `cancelled` | `transaction.cancelled` |
| `expired` | `transaction.expired` (status `expired`) |
| `refused` | `transaction.refused` (status `refused`) |
| `refunded` | `transaction.refunded` |
| `partial_refunded` | `transaction.partially_refunded` |
| `chargedback` | `transaction.chargedback` |

## Cenários compostos

```bash
# Testar dedup — envia o mesmo evento 3x
bash tools/webhook-tester/send.sh paid && \
bash tools/webhook-tester/send.sh paid && \
bash tools/webhook-tester/send.sh paid
# Esperado: 3x HTTP 200 mas só 1 linha em pagou_webhook_events

# Fora de ordem — refund antes de paid
bash tools/webhook-tester/send.sh refunded && \
bash tools/webhook-tester/send.sh paid
# Esperado: handler trata sem rebaixar status final
```
