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

- [ ] **Alertas configurados.**
  - `pagou.webhook.error` > 0 em janela de 5 min
  - `pagou_pix_transactions` em `pending` há mais de 24h
  - Latência p95 de `POST /api/pagou/pix` > 3s
  - 0 webhooks recebidos em 24h em horário comercial (sinal de webhook quebrado)

- [ ] **Dashboard de observabilidade.** Painel com:
  - Volume de cobranças criadas por hora
  - Taxa de conversão (created → paid)
  - Volume de webhooks recebidos
  - Erros recentes

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
