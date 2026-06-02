# Prompt — Validation (Fase 5)

**Objetivo:** validar a integração contra os 5 checklists obrigatórios e registrar evidências.

## Checklists a executar

Para cada um, percorrer todos os itens e marcar ✓ ou ✗ com evidência mínima.

| Arquivo | Categoria |
|---|---|
| `checklists/security.md` | Segredos, headers, logs, payload |
| `checklists/webhook.md` | Recepção, dedup, persistência, ACK rápido, idempotência |
| `checklists/reconciliation.md` | GET fallback, job noturno, no-regress de status |
| `checklists/validation.md` | Testes, cobertura, status mapping |
| `checklists/production.md` | Env vars, monitoring, alertas, runbook |

## Formato de evidência

Para cada item, registrar:

```markdown
- [x] PAGOU_API_KEY apenas lida via `process.env` no servidor
      Evidência: src/lib/pagou/client.ts:14 — `process.env.PAGOU_API_KEY`
      Evidência: nenhuma ocorrência em arquivos client (grep negativo)
```

ou

```markdown
- [ ] Webhook responde < 1s em 95% dos casos
      Status: não medido
      Plano: instrumentar com métrica `pagou_webhook_duration_ms` e re-avaliar após 24h em produção
```

## Itens críticos vs. não-críticos

**Críticos (✗ bloqueia liberação):**

- API key não exposta
- `.env` no `.gitignore`
- Dedup por `event.id` (top-level)
- Webhook ACK ≤ 5s
- Tabela `pagou_webhook_events` com `event_id` UNIQUE
- Status final do pedido confirmado por webhook (não por sucesso do browser)
- Valores em centavos
- Testes do fluxo crítico passando

**Não-críticos (✗ permitido com justificativa documentada):**

- Job noturno de reconciliação (pode ser feito manualmente nas primeiras semanas)
- Alertas (pode ser feito após estabilização)
- Métricas detalhadas
- Reconciliação automática vs. comando manual

## Saída desta fase

- 5 arquivos de checklist preenchidos (na pasta da Skill, em modo "instância" — preservar templates originais)
- `PAGOU_PIX_INTEGRATION_REPORT.md` na raiz do projeto-alvo, consolidando evidências
- Se houver críticos ✗, **não avançar para scoring** — voltar e corrigir

## Critério de saída

- Todos os críticos ✓
- Não-críticos ✗ ≤ 30% do total da categoria
- Justificativas documentadas para todos os ✗
