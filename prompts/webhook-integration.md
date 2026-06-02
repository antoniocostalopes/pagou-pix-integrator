# Prompt — Webhook Integration (Fase 3.b)

**Objetivo:** implementar endpoint que recebe webhooks da Pagou, deduplicar por `event.id` (top-level), persistir e processar de forma assíncrona.

## Contrato do webhook (transação)

A Pagou envia:

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

### Os 3 ids dentro do payload

| Campo | É o id de | Para que serve |
|---|---|---|
| `id` (top-level) | **evento** | **DEDUPLICAÇÃO** — único por entrega |
| `data.id` | transação | Localizar `pagou_pix_transactions` |
| `data.correlation_id` | pedido (== `external_ref`) | Localizar o pedido interno |

**Regra inegociável (PRD):** dedupe sempre por `event.id`. Nunca por `data.id` nem `data.correlation_id`. Uma mesma transação emite vários eventos (`created`, `pending`, `paid`); um mesmo pedido pode ter múltiplas transações (recriação após expiração).

## Endpoint

```
POST {public_url}/webhooks/pagou
```

Sem auth de sessão. Idealmente protegido por allowlist de IP ou HMAC se Pagou expuser cabeçalho de assinatura (validar contra OpenAPI antes de codar — se não documentado, não inventar).

## Fluxo do handler

```
1. Parse JSON do corpo
2. Validar:
   - event === "transaction"
   - id (top-level) não vazio
   - data presente
   Se falhar QUALQUER → responder 200 { received: true } e parar
   (Pagou não deve re-enviar por validação que falhou no cliente)
3. INSERT em pagou_webhook_events com event_id UNIQUE
   Se falhar por UNIQUE (dupla entrega) → responder 200 { received: true } e parar
4. Enqueue job assíncrono (passa apenas event_id, não payload inteiro)
5. Responder 200 { received: true } imediatamente
```

**Tempo total no handler: < 1 segundo no caso comum.**

## Fluxo do job assíncrono

```
1. SELECT * FROM pagou_webhook_events WHERE event_id = ?
2. Se processed_at não nulo → retornar (já processado)
3. Ler data do payload
4. UPDATE pagou_pix_transactions
   SET status = data.status, updated_at = NOW()
   WHERE pagou_transaction_id = data.id
5. Switch (data.event_type):
   - transaction.paid       → marcar pedido como pago (status interno)
   - transaction.cancelled  → marcar pedido como cancelado
   - transaction.refunded   → marcar pedido como estornado
   - transaction.chargedback→ marcar pedido como chargeback + alertar
   - transaction.pending    → no-op (já está pendente)
   - transaction.created    → no-op (já tratado pela criação)
   - transaction.three_ds_required → no-op (não aplica a PIX, ignorar)
6. UPDATE pagou_webhook_events SET processed_at = NOW() WHERE event_id = ?
7. Logar resultado
```

## ACK rápido

Responder **antes** de processar a lógica de negócio:

```json
{ "received": true }
```

Com status `200`. **Sempre** — mesmo quando o evento é ignorado intencionalmente. Isso evita retentativas desnecessárias da Pagou.

## Estratégia de fila por stack

| Stack | Como enfileirar |
|---|---|
| Next.js (App Router) | Inngest, Trigger.dev, Vercel Queues; para POC, `void asyncFn()` mas registrar o débito técnico no relatório |
| Laravel | `dispatch(new ProcessPagouEvent($eventId))` com `ShouldQueue` |
| WordPress | `wp_schedule_single_event(time()+1, 'pagou_pix_process_event', [$event_id])` |
| WooCommerce | mesmo do WP |
| Django | Celery `process_pagou_event.delay(event_id)` |
| FastAPI | `BackgroundTasks` para POC, Celery/Arq em prod |
| Rails | `ProcessPagouEventJob.perform_later(event_id)` (Sidekiq) |
| Express/Fastify | BullMQ ou Agenda |
| Go | goroutine + canal limitado (com persistência outbox para resiliência) |

## Garantias de idempotência

A coluna `event_id UNIQUE` em `pagou_webhook_events` é a **fonte de verdade**. O `INSERT` falha em duplicata → retornar 200 sem processar. Não checar com `SELECT` antes de `INSERT` — é race condition.

**Padrão recomendado:**

```sql
INSERT INTO pagou_webhook_events (event_id, event_type, resource_id, correlation_id, payload)
VALUES (?, ?, ?, ?, ?)
ON CONFLICT (event_id) DO NOTHING;
```

(Em MySQL: `INSERT IGNORE`. Em SQL Server: `IF NOT EXISTS … INSERT`.)

## Ordem de eventos

A Pagou pode entregar eventos fora de ordem (raro, mas possível). Tratamento:

- O job lê o **payload do evento** que ele está processando
- Atualiza `pagou_pix_transactions.status` com o status **deste** evento — sem checar se é "mais novo"
- A regra de negócio (orders) só observa `transaction.paid` → `transaction.refunded`. Não rebaixar status de `paid` para `pending` se chegar atrasado

Se preciso de exatidão temporal, comparar `updated_at` do evento contra timestamp local — fora do escopo padrão da Skill.

## Logs estruturados

```json
{ "event": "pagou.webhook.received", "event_id": "evt_pay_1001", "event_type": "transaction.paid", "resource_id": "tr_1001" }
{ "event": "pagou.webhook.duplicate", "event_id": "evt_pay_1001" }
{ "event": "pagou.webhook.processed", "event_id": "evt_pay_1001", "elapsed_ms": 42 }
{ "event": "pagou.webhook.error", "event_id": "evt_pay_1001", "error": "..." }
```

## Saída desta fase

- Endpoint funcional respondendo `200 { received: true }`
- Tabela `pagou_webhook_events` recebendo eventos
- Tabela `pagou_pix_transactions` atualizando status
- Pedido sendo atualizado quando `transaction.paid` chega
- Teste manual: simular POST duas vezes do mesmo `evt_id` → apenas 1 linha em `pagou_webhook_events`
