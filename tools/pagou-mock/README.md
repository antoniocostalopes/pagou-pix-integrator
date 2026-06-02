# Pagou Mock Server

Servidor HTTP local que **simula a API v2 da Pagou** para desenvolvimento e testes offline. Implementa as rotas que a Skill usa:

- `POST /v2/transactions` — criar cobrança PIX
- `GET /v2/transactions/:id` — consultar
- `POST /v2/transactions/:id/cancel` — cancelar
- `POST /v2/transactions/:id/refund` — estornar

E dispara **webhooks de volta** para o teu endpoint, com assinatura HMAC.

## Iniciar

```bash
cd tools/pagou-mock
node server.js
```

Por defeito escuta em `http://localhost:4242` e envia webhooks para `http://localhost:3000/api/webhooks/pagou`.

Configurável via env:

```bash
PORT=4242                                                  # porta do mock
WEBHOOK_URL=http://localhost:3000/api/webhooks/pagou      # destino dos webhooks
WEBHOOK_SECRET=dev-secret-please-change                    # mesmo que PAGOU_WEBHOOK_SECRET no teu app
WEBHOOK_DELAY_MS=2000                                      # atraso antes de enviar webhook (simula tempo de pagamento)
```

## Usar no teu app

Aponta o cliente Pagou para o mock:

```bash
PAGOU_BASE_URL=http://localhost:4242
PAGOU_API_KEY=mock-key-anything-works
PAGOU_WEBHOOK_SECRET=dev-secret-please-change
```

Cria uma cobrança normalmente; o mock:

1. Devolve resposta com `pix_qr_code` (placeholder base64) e `pix_code`
2. Após `WEBHOOK_DELAY_MS`, envia `transaction.pending` para o teu webhook
3. Após mais `WEBHOOK_DELAY_MS`, envia `transaction.paid` automaticamente

Para simular cenários específicos (expired, refused, chargeback), ver `payloads/`.

## Cenários pré-definidos

| Trigger | Comportamento |
|---|---|
| `external_ref` começa por `expire-` | Webhook `transaction.expired` em vez de paid |
| `external_ref` começa por `refuse-` | Webhook `transaction.refused` |
| `external_ref` começa por `chargeback-` | Webhook `transaction.paid` seguido de `transaction.chargedback` 30s depois |
| `external_ref` começa por `slow-` | Webhook leva 30s em vez de 2s |
| `external_ref` começa por `silent-` | Nenhum webhook enviado (testa reconciliação) |

## Implementação

Ver `server.js` (Node 20+, zero dependências externas — só `node:*`).
