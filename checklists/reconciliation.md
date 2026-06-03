# Checklist — Reconciliação

**Aplicabilidade:** sempre aplica, mas com **rigor diferente conforme o modo**:

- **Modo `webhook` (default):** reconciliação é **fallback** — corre horária, apanha webhooks perdidos. Items "Críticos" obrigatórios; "Importantes" recomendados.
- **Modo `polling`:** reconciliação é o **único caminho** para detectar eventos pós-terminal (`refunded`, `partially_refunded`, `chargedback`). **Todos os itens "Críticos" + "Importantes" são obrigatórios.** Adicionalmente, há novo item crítico abaixo sobre o **background poller curto** que é específico do modo polling.

## Crítico em modo `polling` (não aplicável em webhook)

- [ ] **Background poller curto agendado.** Job que corre cada 1 minuto, consulta `GET /v2/transactions/{id}` para transações `pending`/`created` criadas na última 1h, e propaga status terminais para o pedido.
  - Verificar que está agendado (via scheduler do framework: `vercel.json crons`, `php artisan schedule:list`, `wp cron event list`, etc.)
  - Cobertura: 100% das transações pending dentro da janela de 1h passam por este job
  - Limite máximo de execução: < 30s por iteração (não bloquear o scheduler)
  - Teste manual: criar PIX via `tools/pagou-mock/` → mock fica em status pending → aguardar 2 min → simular pagamento no mock (curl ao endpoint de simulação) → confirmar que sistema interno passa a `paid` via poller

- [ ] **`pagou:reconcile-late` corre a cada 15 min** (em vez de horária do modo webhook).
  - Janela: transações terminais criadas nos últimos 30 dias
  - Propaga refunded/partially_refunded/chargedback para o pedido

## Críticos

- [ ] **Função `reconcile(transaction_id)` existe** e chama `GET /v2/transactions/:id` na Pagou.

- [ ] **Atualização idempotente.** Reconciliação **não** rebaixa status terminais (uma transação `paid` não volta para `pending` se a Pagou momentaneamente retornar um snapshot antigo).

- [ ] **Reconciliação propaga para o pedido.** Quando o status atualiza para `paid` por reconciliação (e o pedido ainda não está pago), o pedido é marcado como pago — **uma única vez** (sem disparar e-mails duplicados se webhook chegar depois).

## Importantes

- [ ] **Endpoint admin de reconciliação manual.** `POST /admin/pagou/reconcile/:transaction_id`, autenticado, com resposta clara.

- [ ] **Job noturno (ou hourly) agendado.** Reconcilia transações em `pending` há mais de 1h e menos de 30 dias. Documentado em `README_PAGOU_PIX.md`.

- [ ] **Rate limiting do job.** `sleep` de 100ms entre chamadas, ou batch de 50 com pausa, para não estressar a Pagou.

- [ ] **Logs estruturados** com `transaction_id`, `previous`, `current` em cada reconciliação.

- [ ] **Reconciliação não é fluxo principal.** Frontend **não** chama reconciliação — apenas o backend (job, admin, suporte).

## Recomendados

- [ ] **Dashboard com contadores:**
  - Transações reconciliadas hoje
  - Reconciliações que mudaram status
  - Reconciliações que falharam

- [ ] **Métrica de "drift"** — porcentagem de transações cujo status divergiu até a reconciliação. Indica saúde do webhook.

- [ ] **Reconciliação por `external_ref`** (busca de transação pelo id do pedido) — útil para casos onde perdemos `pagou_transaction_id`. Verificar se Pagou suporta listar por `external_ref`; se não, deixar como follow-up.

## Cenários validados

- [ ] Transação stale (`pending` há 2h) → reconcilia, encontra `paid`, atualiza pedido
- [ ] Transação `paid` há semanas → reconcilia, mantém `paid`, no-op no pedido (já estava pago)
- [ ] Pagou retorna 404 → log warning, não derruba job
- [ ] Pagou retorna 5xx → retry curto (1 vez), depois log e segue
- [ ] Timeout → log e segue (não bloqueia outras reconciliações no batch)

## Política de reprocessamento

- Reconciliação **não** dispara entrega de produto se o pedido já foi entregue
- Reconciliação **não** envia e-mail de confirmação se já foi enviado
- A transição "pendente → pago" detectada por reconciliação **deve** disparar os mesmos efeitos colaterais que o webhook (entrega, e-mail, etc.) — exceto se já foram disparados

Implementação típica: marca booleano `order.paid_notification_sent` ou similar para evitar duplicação.

## Saída

```markdown
- [x] {{item}}
      Evidência: {{onde}}
```
