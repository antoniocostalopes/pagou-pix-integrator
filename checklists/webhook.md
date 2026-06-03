# Checklist — Webhook

**Aplicabilidade:** este checklist aplica-se na íntegra **se `PAGOU_CONFIRMATION_MODE=webhook`** (default). Em modo `polling`, o endpoint continua a existir e os itens de implementação (HMAC, dedup, validação) **continuam a ser verificados** (porque o código tem de estar correcto caso o utilizador active webhook depois), mas os itens operacionais (registo no painel, teste de entrega real) são marcados N/A com nota *"diferido — modo polling activo"*. Em paralelo, validar `checklists/reconciliation.md` que passa a ser onde mora a confiança do pagamento.

## Críticos

- [ ] **Endpoint público acessível.** `POST {{PUBLIC_URL}}/api/webhooks/pagou` retorna `200 { received: true }` com qualquer JSON válido — testado com `curl` real do exterior.

- [ ] **Verificação HMAC da assinatura.**
  - Header `X-Pagou-Signature` validado contra `HMAC-SHA256(rawBody, PAGOU_WEBHOOK_SECRET)`
  - Comparação em **tempo constante** (`timingSafeEqual`, `hash_equals`, `secrets.compare_digest`)
  - Assinatura inválida → resposta `401` + payload **não** persiste
  - Em produção (detectado pelo runtime do framework: `NODE_ENV=production` / `APP_ENV=production` / etc.) sem `PAGOU_WEBHOOK_SECRET` → boot falha (fail closed). Skill v3+ não usa `PAGOU_ENV`.
  - Em dev sem secret → log warning + permitido (fail open)
  - Body cru usado no cálculo (não o JSON parseado)
  - Teste: assinatura forjada → 401 + nada persistido

- [ ] **Dedup por `event.id` (top-level).**
  - Tabela `pagou_webhook_events` com `event_id` UNIQUE
  - `INSERT ... ON CONFLICT DO NOTHING` (ou equivalente do banco)
  - **NÃO** usa `data.id` (transação) para dedup
  - **NÃO** usa `data.correlation_id` (pedido) para dedup
  - Teste: 2 POST com mesmo `event.id` → 1 linha

- [ ] **ACK rápido.** Resposta `{ received: true }` é enviada **antes** de qualquer processamento pesado.
  - Latência p95 < 1s
  - Latência p99 < 3s
  - Limite máximo 5s (Pagou pode considerar timeout)

- [ ] **Processamento assíncrono.** Lógica de atualizar pedido roda em job/fila/background, não no handler.

- [ ] **Validação mínima do payload.**
  - `event === "transaction"` para fluxo PIX
  - `id` (top-level) presente e não-vazio
  - `data` é objeto
  - Falha de validação → 200 (não 4xx) para evitar retry

## Importantes

- [ ] **Todos os eventos relevantes são tratados:**
  - `transaction.created` → no-op (já criamos)
  - `transaction.pending` → no-op (já está pending)
  - `transaction.paid` → marcar pedido como pago ← **mais importante**
  - `transaction.cancelled` → marcar pedido como cancelado
  - `transaction.refunded` → marcar pedido como estornado
  - `transaction.chargedback` → marcar como chargeback + alertar
  - `transaction.three_ds_required` → ignorar (não aplica PIX)

- [ ] **Persistência completa do payload.** `pagou_webhook_events.payload` guarda o JSON cru para auditoria/reprocesso.

- [ ] **Coluna `processed_at`.** É preenchida após sucesso. Permite identificar eventos órfãos.

- [ ] **Retry idempotente do job.** Se o job falhar e re-tentar, não duplica efeito (UPDATE com `WHERE status != "paid"` ou similar).

- [ ] **Logs estruturados** com `event_id` e `event_type` em cada passo.

## Recomendados

- [ ] **Dead-letter queue / outbox.** Eventos que falharem N vezes vão para inspeção manual em vez de loop infinito.

- [ ] **Allowlist de IP / HMAC** se Pagou fornecer (verificar docs/OpenAPI).

- [ ] **Métrica de tempo de processamento** do job (`pagou.webhook.processing_ms`).

- [ ] **Re-trigger manual** — endpoint admin para reprocessar um `event_id` (útil para corrigir bugs em produção).

## Casos negativos validados

- [ ] POST sem `event === "transaction"` → 200, não insere
- [ ] POST sem `id` top-level → 200, não insere
- [ ] POST com JSON inválido → 400, não derruba o servidor
- [ ] POST com payload enorme (1MB+) → tratado sem OOM
- [ ] POST com `event_type` desconhecido → 200, persiste mas no-op no processamento

## Evidência típica

```markdown
- [x] Dedup por `event.id` (top-level)
      Evidência: `app/api/webhooks/pagou/route.ts:36–44` usa `prisma.pagouWebhookEvent.create` com unique constraint
      Teste: `tests/pagou/webhook.test.ts:23-40` — POST duplicado, 1 linha verificada
```
