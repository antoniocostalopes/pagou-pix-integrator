# Prompt — Reconciliation (Fase 3.c)

**Objetivo:** garantir que estados ambíguos ou perdidos possam ser recuperados via `GET /v2/transactions/{id}`.

## Quando usar reconciliação

Cenário | Ação
---|---
Webhook perdido (Pagou tentou entregar e falhou) | Reconciliar transação após X minutos sem update
Resposta da Pagou perdida no `POST /v2/transactions` (timeout) | Reconciliar usando `external_ref` (se Pagou suportar listing por `external_ref`) ou re-tentar criação idempotente
Suporte ao cliente perguntando "paguei mas não atualizou" | Reconciliar manualmente
Job noturno de saúde | Reconciliar todas as transações em `pending` há mais de 24h

## Reconciliação não é o fluxo principal

**PRD:** "Use GET polling only for reconciliation, support, or recovery, never as the primary flow."

Concretamente: **nunca** mover um pedido para "pago" sem evento de webhook ou GET de reconciliação. **Nunca** ficar fazendo `setInterval(checkStatus, 5000)` no frontend.

## Serviço de reconciliação

Contrato:

```pseudo
reconcile(pagou_transaction_id: string):
    tx = pagouFetch("GET", "/v2/transactions/" + pagou_transaction_id)

    UPDATE pagou_pix_transactions
       SET status = tx.status,
           raw_response = tx,
           updated_at = NOW()
       WHERE pagou_transaction_id = pagou_transaction_id

    # Propagar para o pedido se virou terminal
    if tx.status in ["paid","cancelled","expired","refused","refunded","chargedback"]:
        UPDATE orders
           SET status = map_status(tx.status)
           WHERE id = tx.external_ref
           AND status NOT IN ("paid","cancelled","refunded","chargedback")
        # acima: idempotência — não rebaixa terminais
```

Importante:

- Reconciliação **não** dispara emails / entrega de produto se o pedido **já** está como pago. Apenas o webhook fez isso.
- Se a reconciliação descobrir que está pago e o pedido ainda **não** foi processado → tratar como se fosse o evento `transaction.paid` chegando atrasado (rodar a mesma lógica do job de webhook)

## Endpoint admin

Expor (atrás de auth admin do projeto):

```
POST /admin/pagou/reconcile/:pagou_transaction_id
```

Resposta:

```json
{
  "transaction_id": "tr_1001",
  "previous_status": "pending",
  "current_status": "paid",
  "order_updated": true
}
```

## Job noturno

Pseudocódigo:

```pseudo
nightly_reconcile():
    candidates = SELECT pagou_transaction_id FROM pagou_pix_transactions
                 WHERE status = 'pending'
                 AND created_at < NOW() - INTERVAL 1 HOUR
                 AND created_at > NOW() - INTERVAL 30 DAY
    for tx in candidates:
        try:
            reconcile(tx.pagou_transaction_id)
        catch e:
            log_warn("reconcile failed", tx_id=tx, error=e)
        sleep 100ms  # rate limit gentle
```

Frequência: 1× por hora ou 1× por noite. Ajustar conforme volume.

## Estratégia por stack

| Stack | Onde rodar o job |
|---|---|
| Next.js | Cron job na Vercel (`vercel.json` `crons`) ou Inngest scheduled function |
| Laravel | `app/Console/Kernel.php` schedule `->hourly()` |
| WordPress | `wp_schedule_event(time(), 'hourly', 'pagou_pix_reconcile_cron')` |
| Django | Celery beat |
| FastAPI | APScheduler ou cron externo |
| Rails | `whenever` ou Sidekiq Cron |
| Go / .NET | cronjob externo (k8s CronJob, systemd timer) |

## O que **não** fazer

| ❌ | Por quê |
|---|---|
| `while (status === "pending") fetchStatus()` no client | Não é fluxo principal — webhook é |
| Re-tentar `POST /v2/transactions` em loop quando der erro | Pode duplicar cobrança (mesmo com `external_ref`, idempotência depende do servidor) — use GET para confirmar |
| Reconciliar a cada 5 minutos em prod com 10k transações abertas | Sobrecarrega a Pagou; usar dedup por timestamp + janela |
| Mover pedido de `paid` → `pending` se reconciliação acidentalmente trouxer status antigo | Status terminal não regride |

## Logs

```json
{ "event": "pagou.reconcile.start",  "transaction_id": "tr_1001" }
{ "event": "pagou.reconcile.result", "transaction_id": "tr_1001", "previous": "pending", "current": "paid" }
{ "event": "pagou.reconcile.error",  "transaction_id": "tr_1001", "error": "..." }
```

## Saída desta fase

- Função/serviço `reconcile(transaction_id)` implementado
- Endpoint admin disponível
- Job noturno agendado e documentado em `README_PAGOU_PIX.md`
- Teste: simular cenário "webhook não chegou" → reconciliar manualmente → pedido atualiza
