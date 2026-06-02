# Webhook Flow — detalhe do handler

Aprofunda o que acontece quando a Pagou entrega um evento.

## Estrutura do evento (transação)

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

### Os 3 ids — mapa mental

```
evt_pay_1001  ← id do EVENTO (esta entrega específica)
              ↓ dedup por isto
              
tr_1001       ← id da TRANSAÇÃO (Pagou)
              ↓ localizar nossa pagou_pix_transactions

order_1001    ← correlation_id (= nosso external_ref)
              ↓ localizar o pedido (orders)
```

Uma transação emite N eventos:
- `transaction.created` (evt_A)
- `transaction.pending` (evt_B)
- `transaction.paid` (evt_C)

Todos têm `data.id = tr_1001` mas `id` distintos. **Dedup por `id` (evento)** garante que cada um seja processado exatamente uma vez.

## Fluxo do handler — diagrama detalhado

```
┌──────────────────────────────────────────────────────────────┐
│ POST /webhooks/pagou                                         │
│                                                              │
│  ┌─────────────────────┐                                     │
│  │ parse JSON body     │                                     │
│  └──────────┬──────────┘                                     │
│             │                                                │
│             ▼                                                │
│  ┌─────────────────────┐    invalid                          │
│  │ event === "transac- ├───────► 200 { received: true }      │
│  │ tion" && id?        │         (Pagou não re-tenta)        │
│  └──────────┬──────────┘                                     │
│        valid│                                                │
│             ▼                                                │
│  ┌─────────────────────┐    UNIQUE violation                 │
│  │ INSERT pagou_       ├───────► 200 { received: true }      │
│  │ webhook_events      │         (já processado antes)       │
│  │ ON CONFLICT NOOP    │                                     │
│  └──────────┬──────────┘                                     │
│        inserted                                              │
│             ▼                                                │
│  ┌─────────────────────┐                                     │
│  │ enqueue ProcessEvent│                                     │
│  │   Job(event_id)     │                                     │
│  └──────────┬──────────┘                                     │
│             │                                                │
│             ▼                                                │
│  ┌─────────────────────┐                                     │
│  │ 200 { received: true}                                     │
│  └─────────────────────┘                                     │
│                                                              │
│  (tempo total < 200ms idealmente)                            │
└──────────────────────────────────────────────────────────────┘
```

## Job — diagrama detalhado

```
┌──────────────────────────────────────────────────────────────┐
│ ProcessPagouEvent(event_id)                                  │
│                                                              │
│  SELECT * FROM pagou_webhook_events WHERE event_id = ?       │
│             │                                                │
│             ▼                                                │
│  processed_at IS NOT NULL? ──── yes ──► return (idempotente) │
│             │                                                │
│             no                                               │
│             ▼                                                │
│  data = payload.data                                         │
│             │                                                │
│             ▼                                                │
│  UPDATE pagou_pix_transactions                               │
│    SET status = data.status, updated_at = NOW()              │
│    WHERE pagou_transaction_id = data.id                      │
│             │                                                │
│             ▼                                                │
│  switch(data.event_type):                                    │
│    case "transaction.paid":                                  │
│      UPDATE orders                                           │
│        SET status = mapStatus("paid")                        │
│        WHERE id = data.correlation_id                        │
│        AND status NOT IN ("pago","cancelado")  ← no-regress  │
│      enqueue side effects (email, delivery)                  │
│                                                              │
│    case "transaction.cancelled":                             │
│    case "transaction.refunded":                              │
│    case "transaction.chargedback":                           │
│      UPDATE orders SET status = ...                          │
│                                                              │
│    case "transaction.pending":                               │
│    case "transaction.created":                               │
│    case "transaction.three_ds_required":                     │
│      no-op                                                   │
│             │                                                │
│             ▼                                                │
│  UPDATE pagou_webhook_events                                 │
│    SET processed_at = NOW()                                  │
│    WHERE event_id = ?                                        │
└──────────────────────────────────────────────────────────────┘
```

## Por que UNIQUE constraint, não SELECT-then-INSERT

```
❌ Errado (race condition):
  if not exists(select where event_id = X):
      insert event_id = X
  
  Duas chamadas simultâneas podem passar ambas pelo "not exists" e inserir duas linhas.

✓ Correto:
  insert event_id = X on conflict do nothing
  → o banco garante atomicidade. Idempotente por construção.
```

## Por que processar async

| Cenário | Síncrono | Assíncrono |
|---|---|---|
| Pagou demora 5s para processar | ❌ timeout, Pagou re-envia, dedup salva mas geramos carga | ✓ ACK em 50ms |
| Job demora 30s (e-mail SMTP lento) | ❌ Pagou considera timeout | ✓ processa em background |
| Erro temporário no nosso DB | ❌ retornamos 500, Pagou re-envia, dedup detecta e ignora — mas evento fica órfão | ✓ job re-tenta na fila |

## Side effects — princípio

Side effects (entregar produto, enviar e-mail, notificar terceiros) devem rodar **uma única vez** mesmo se webhook for retransmitido ou reconciliação detectar tardiamente.

Padrão recomendado:

```sql
UPDATE orders
   SET status = 'pago',
       paid_notification_sent_at = COALESCE(paid_notification_sent_at, NOW())
 WHERE id = ?
   AND status != 'pago';
```

Depois:

```pseudo
order = SELECT * FROM orders WHERE id = ?
if order.status == 'pago' AND order.paid_notification_sent_at == this_event_time:
    # acabamos de transicionar
    enqueue send_email(order)
    enqueue deliver_product(order)
```

Ou use uma tabela `order_events` com `event_type UNIQUE per order`.

## Quando webhook NÃO chega

```
T+0    cobrança criada, status=pending
T+1m   cliente paga
T+1m   Pagou tenta entregar webhook
T+1m   nosso servidor offline
T+5m   Pagou re-tenta — nosso servidor ainda offline
T+15m  Pagou desiste (ou continua tentando, depende da política)

T+1h   job de reconciliação roda:
         GET /v2/transactions/tr_X → status=paid
         UPDATE pagou_pix_transactions.status = paid
         UPDATE orders WHERE id=external_ref AND status != 'pago' SET status = 'pago'
         (se mudou) → dispara side effects

T+1h2m cliente recebe confirmação por e-mail (atrasado, mas chega)
```

## Anti-padrões frequentes

| ❌ Errado | Por que | ✓ Correto |
|---|---|---|
| `WHERE data.id = ?` para dedup | Uma transação emite N eventos; iríamos descartar `paid` se já tivéssemos `pending` da mesma tr | Dedup por `event.id` |
| Processar dentro do handler | Pode passar de 5s; Pagou re-envia | Enfileirar |
| `SELECT then INSERT` em vez de UNIQUE | Race condition | UNIQUE + ON CONFLICT |
| Rebaixar `paid → pending` se evento atrasado chegar | Ordem de eventos não é garantida | Não regredir status terminais |
| Disparar entrega 2x se webhook re-chegar | Não usar UNIQUE | UNIQUE event_id resolve |
