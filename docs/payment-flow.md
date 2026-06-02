# Payment Flow — PIX via Pagou

Fluxo end-to-end de uma cobrança PIX, do clique no checkout até a entrega confirmada.

## Sequência completa

```
Cliente            Frontend           Backend            Pagou.ai
   │                  │                  │                  │
   │ 1. clica "PIX"   │                  │                  │
   ├─────────────────►│                  │                  │
   │                  │ 2. POST /api/pagou/pix              │
   │                  │   { orderId }    │                  │
   │                  ├─────────────────►│                  │
   │                  │                  │ 3. POST /v2/transactions
   │                  │                  │   { external_ref, amount, method:pix, buyer }
   │                  │                  ├─────────────────►│
   │                  │                  │                  │
   │                  │                  │  4. 200 { id, status:pending, pix_qr_code, pix_code }
   │                  │                  │◄─────────────────┤
   │                  │                  │                  │
   │                  │                  │ 5. UPSERT pagou_pix_transactions
   │                  │                  │   (external_ref UNIQUE)
   │                  │                  │                  │
   │                  │ 6. 200 { transaction_id, status, pix_qr_code, pix_code }
   │                  │◄─────────────────┤                  │
   │                  │                  │                  │
   │ 7. vê QR + copia │                  │                  │
   │◄─────────────────┤                  │                  │
   │                  │                  │                  │
   │ 8. abre app banco, paga PIX                            │
   │                  │                                     │
   │   (cliente vê app dele atualizar — independente de nós)│
   │                                                        │
   │                                     9. POST /webhooks/pagou
   │                                        { id:evt_X, event:transaction,
   │                                          data:{event_type:transaction.paid,
   │                                                id:tr_X, status:paid,
   │                                                correlation_id:order_X} }
   │                                     │◄─────────────────┤
   │                                     │                  │
   │                                     │ 10. INSERT pagou_webhook_events (UNIQUE event_id)
   │                                     │ 11. enqueue job
   │                                     │ 12. 200 { received:true }
   │                                     ├─────────────────►│
   │                                     │                  │
   │                                     │ ── async ──      │
   │                                     │ 13. UPDATE pagou_pix_transactions SET status=paid
   │                                     │ 14. UPDATE orders SET status=pago WHERE id=correlation_id
   │                                     │ 15. UPDATE pagou_webhook_events SET processed_at=NOW()
   │                                     │ 16. dispara entrega, e-mail, etc.
   │                                     │                  │
   │                  │ 17. polling/SSE detecta order.status=pago
   │                  │◄────────────────┤                   │
   │                  │                                     │
   │ 18. UX: "pagamento confirmado"                         │
   │◄─────────────────┤                                     │
```

## Por que cada passo está aqui

| # | Passo | Por que é assim |
|---|---|---|
| 2 | Frontend não chama Pagou direto | API key não pode estar no browser |
| 3 | `external_ref` = `orderId` | Idempotência e reconciliação |
| 5 | Upsert, não insert | Idempotência se cliente clicar 2x |
| 7 | Cliente vê QR | UX padrão PIX — copia-e-cola ou scan |
| 8 | Cliente paga fora | Sem nossa interferência |
| 9 | Pagou avisa por webhook | Estado autoritativo |
| 10 | UNIQUE em `event_id` | Dedup mesmo se Pagou enviar 2x |
| 11 | Job assíncrono | ACK rápido (Pagou pode considerar timeout > 5s) |
| 12 | ACK antes do processamento | Mesmo motivo |
| 14 | `correlation_id` → order | Esse campo é o `external_ref` ecoado |
| 16 | Side effects no job | Atômico com o UPDATE — se job falhar, sem entrega errada |
| 17 | Frontend polling/SSE | Não confiar em sucesso do passo 6 — só estado pós-webhook |

## Fluxo com expiração

```
... (passos 1–8 iguais)
   │ cliente NÃO paga (deixa expirar)
   │                                     
   │                                     POST /webhooks/pagou
   │                                     { id:evt_Y, event:transaction,
   │                                       data:{event_type:transaction.cancelled (ou expired),
   │                                             id:tr_X, status:expired, correlation_id:order_X} }
   │                                     │
   │                                     INSERT event, UPDATE status=expired, UPDATE order=expirado
   │
   │ Frontend mostra "cobrança expirada, criar nova"
```

## Fluxo com chargeback

```
... (passos 1–18 iguais, pedido foi para "pago")
   │
   │ semanas depois, cliente abre disputa no banco
   │                                     
   │                                     POST /webhooks/pagou
   │                                     { id:evt_Z, event:transaction,
   │                                       data:{event_type:transaction.chargedback,
   │                                             id:tr_X, status:chargedback, correlation_id:order_X} }
   │
   │                                     UPDATE order=chargeback
   │                                     Alerta para o time financeiro
```

## Fluxo com webhook perdido

```
... (passos 1–6 iguais)
   │ cliente paga, mas Pagou tenta entregar webhook e nosso servidor estava offline
   │
   │ ... pedido fica em "pending" no nosso lado, "paid" no lado da Pagou
   │
   │ Após 1h, job de reconciliação roda:
   │                                     
   │                                     GET /v2/transactions/tr_X
   │                                     │
   │                                     200 { status: paid, ... }
   │
   │                                     UPDATE pagou_pix_transactions SET status=paid
   │                                     UPDATE order SET status=pago
   │                                     dispara entrega, e-mail (se ainda não disparado)
   │
   │ Cliente recebe confirmação (talvez 1h atrasada, mas chega)
```

## Por que não polling no frontend

O frontend **não** deve fazer `GET /v2/transactions/:id` direto na Pagou. Razões:

1. API key estaria exposta
2. Pagou não autoriza chamadas autenticadas do browser
3. Geraria carga desnecessária — webhook resolve

O frontend pode fazer polling de **um endpoint interno** que devolve o status conhecido do pedido (que foi atualizado por webhook). Ou usar SSE/WebSocket para push quando o status muda.

## Estado da verdade

| Sistema | Verdade sobre... |
|---|---|
| Pagou | Status real do PIX |
| `pagou_pix_transactions` | O que a Pagou nos disse mais recentemente |
| `orders` | Estado do pedido no nosso domínio (consequência do PIX) |
| `pagou_webhook_events` | Log auditável de eventos recebidos |

Em caso de divergência, **Pagou é a verdade** — reconciliar via GET.
