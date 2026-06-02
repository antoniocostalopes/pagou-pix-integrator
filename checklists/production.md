# Checklist — Pronto para Produção

## Críticos

- [ ] **Score técnico ≥ 90.** Ver `PAGOU_PIX_INTEGRATION_SCORE.md`. Abaixo disso → não deploy.

- [ ] **Migração aplicada em produção.** Comando do framework executado com sucesso. Tabelas `pagou_pix_transactions` e `pagou_webhook_events` existem.

- [ ] **Variáveis configuradas no ambiente de produção.**
  - `PAGOU_API_KEY` (production key, **não** sandbox)
  - `PAGOU_ENV=production`
  - `PUBLIC_APP_URL` aponta para domínio real https://
  - Validação: cold start sem `Error: PAGOU_API_KEY is not set`

- [ ] **Webhook registrado no painel Pagou produção.** URL aponta para domínio real, eventos selecionados.

- [ ] **Teste de fumaça em produção (com valor mínimo, ex.: R$ 1,00).**
  - Criar cobrança → recebe QR
  - Pagar pelo app do banco
  - Webhook recebido
  - Pedido marcado como pago
  - Cliente recebe confirmação

- [ ] **Rollback documentado em `PAGOU_PIX_INTEGRATION_REPORT.md`.** Procedimento testado em staging.

## Importantes

- [ ] **Métricas Prometheus expostas.** Endpoint `/metrics` (ou equivalente) atrás de auth. Definições em [`docs/observability/metrics.md`](../docs/observability/metrics.md).

- [ ] **Alertas configurados.** Importar regras de [`docs/observability/prometheus-alerts.yml`](../docs/observability/prometheus-alerts.yml). Alertas mínimos:
  - `PagouWebhookErrorsHigh` — erros de processamento >0 por 5 min
  - `PagouWebhookInvalidSignature` — >5 HMACs inválidos em 10 min (ataque ou rotação de secret)
  - `PagouWebhookSilent` — 0 webhooks em 6h em horário comercial
  - `PagouWebhookAckSlow` — p95 ACK > 3s
  - `PagouCreateLatencyHigh` — p95 create > 5s
  - `PagouApiErrorRate` — erros API > 5%
  - `PagouPendingTransactionsHigh` — >20 pending há >1h
  - `PagouReconcileDrift` — >10 drifts em 1h

- [ ] **Dashboard Grafana importado.** Usar [`docs/observability/grafana-dashboard.json`](../docs/observability/grafana-dashboard.json) — 3 linhas (Cobrança · Webhooks · Reconciliação) com 9 painéis prontos.

- [ ] **Job de reconciliação noturna ativo.** Cron rodando + log de última execução.

- [ ] **Runbook para incidentes** em `README_PAGOU_PIX.md`:
  - "Webhook não chega"
  - "Cliente diz que pagou mas pedido não atualizou"
  - "Pagou API retornando 5xx"
  - "API key inválida"

## Recomendados

- [ ] **Canary deploy.** Liberar PIX gradualmente (% de usuários) com feature flag, observar 24h antes de 100%.

- [ ] **Métrica de negócio.** Cliente pode comparar volume PIX vs. cartão depois de N dias.

- [ ] **Documentação para o time de suporte.** "Quando o cliente reclamar de PIX, fazer X" — uma página, com prints.

- [ ] **Política de retenção.** `pagou_webhook_events` cresce indefinidamente; documentar limpeza após N anos.

- [ ] **Conta sandbox separada da conta produção.** Não compartilhar PAGOU_API_KEY entre ambientes.

## Pré-deploy: smoke test em staging

Executar 7 cenários, todos devem passar:

1. Criar cobrança PIX → QR válido
2. Pagar → webhook `transaction.paid` → pedido `pago`
3. Não pagar → webhook `transaction.cancelled` (após expiração) → pedido `cancelado`
4. Cobrança duplicada (mesmo `order_id`) → reusa primeira, não cria nova
5. Webhook duplicado (mesmo `event.id`) → 1 linha em `pagou_webhook_events`
6. Reconciliar manualmente uma transação stale → status atualiza
7. Buscar logs de uma transação por `external_ref` → ≥ 3 eventos logados

## Pós-deploy: monitorar 72h

- Verificar pelo menos 1 cobrança real foi paga e processada end-to-end
- Verificar tempo médio de processamento de webhook < 1s
- Verificar 0 webhooks com `processed_at IS NULL` depois de 5 min
- Verificar nenhuma transação em `pending` após 24h sem reason válida

Se algum check falhar → ativar rollback.
