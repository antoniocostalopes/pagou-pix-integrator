# PAGOU_PIX_INTEGRATION_SCORE

> Score técnico calculado conforme `docs/scoring-engine.md`.

# Score: {{XX}}/100 — **{{Classificação}}**

| Faixa | Classificação |
|---|---|
| 95–100 | Enterprise Ready |
| 90–94 | Production Ready |
| 80–89 | Minor Improvements |
| 70–79 | Needs Review |
| 0–69 | Not Ready |

## Resumo por categoria

| Categoria | Pontos | Máximo | % |
|---|---|---|---|
| Configuração | {{n}} | 15 | {{%}} |
| Arquitetura | {{n}} | 15 | {{%}} |
| PIX | {{n}} | 20 | {{%}} |
| Webhooks | {{n}} | 20 | {{%}} |
| Segurança | {{n}} | 15 | {{%}} |
| Confiabilidade | {{n}} | 15 | {{%}} |
| **Total** | **{{XX}}** | **100** | **{{%}}** |

---

## Detalhes — Configuração ({{n}}/15)

| Critério | Pontos | Status | Evidência |
|---|---|---|---|
| `.env.example` atualizado | 3 / 3 | ✓ | {{`.env.example` linhas X–Y}} |
| `.env` no `.gitignore` | 2 / 2 | ✓ | {{`.gitignore` linha N}} |
| Vars só no servidor (grep negativo) | 3 / 3 | ✓ | {{`grep -r PAGOU_API_KEY src/client → 0`}} |
| Base URL por ambiente | 3 / 3 | ✓ | {{`src/lib/pagou/client.ts:8–11`}} |
| Documentação operacional | {{X}} / 4 | {{✓/✗}} | {{`README_PAGOU_PIX.md`}} |

## Detalhes — Arquitetura ({{n}}/15)

| Critério | Pontos | Status | Evidência |
|---|---|---|---|
| Segue padrão do projeto | 4 / 4 | ✓ | {{services em `src/lib/` — convenção pré-existente}} |
| Nomes de tabela alinhados | 2 / 2 | ✓ | {{snake_case plural}} |
| Logger do projeto | 2 / 2 | ✓ | {{`pino` importado em webhook handler}} |
| Error handling consistente | {{X}} / 3 | {{✓/✗}} | {{evidência}} |
| Separação de camadas | 4 / 4 | ✓ | {{client/service/route distintos}} |

## Detalhes — PIX ({{n}}/20)

| Critério | Pontos | Status | Evidência |
|---|---|---|---|
| Endpoint criar cobrança | 4 / 4 | ✓ | {{path do route}} |
| Valores em centavos | 3 / 3 | ✓ | {{teste `amount.test.ts`}} |
| `external_ref` sempre | 3 / 3 | ✓ | {{linha do payload}} |
| Resposta com QR + code | 2 / 2 | ✓ | {{shape verificado}} |
| Upsert por `external_ref` | 3 / 3 | ✓ | {{linha do prisma upsert}} |
| Status inicial persistido | 2 / 2 | ✓ | {{`status: tx.status`}} |
| Status mapping completo | 3 / 3 | ✓ | {{`src/lib/pagou/status.ts`}} |

## Detalhes — Webhooks ({{n}}/20)

| Critério | Pontos | Status | Evidência |
|---|---|---|---|
| Endpoint público funcional | 3 / 3 | ✓ | {{teste e2e}} |
| ACK rápido `{received:true}` | 3 / 3 | ✓ | {{ordem das instruções no handler}} |
| Tabela com `event_id` UNIQUE | 4 / 4 | ✓ | {{migration `@@unique([eventId])`}} |
| Dedup por `event.id` top-level | 4 / 4 | ✓ | {{teste `webhook.test.ts:23` — `INSERT` por `event.id`}} |
| Processamento assíncrono | {{X}} / 3 | {{✓/✗}} | {{`Inngest` / `dispatch` / etc.}} |
| Eventos relevantes tratados | 3 / 3 | ✓ | {{switch em `event_type`}} |

## Detalhes — Segurança ({{n}}/15)

| Critério | Pontos | Status | Evidência |
|---|---|---|---|
| API key só backend | 4 / 4 | ✓ | {{grep negativo}} |
| Sem segredos commitados | 3 / 3 | ✓ | {{`git log -S PAGOU_API_KEY` vazio}} |
| Logs sem segredos | 3 / 3 | ✓ | {{`grep "Authorization" logs/` vazio}} |
| Payload validado | 2 / 2 | ✓ | {{validação `event === "transaction"`}} |
| HTTPS obrigatório | 3 / 3 | ✓ | {{base URL Pagou é https://; produção atrás de TLS}} |

## Detalhes — Confiabilidade ({{n}}/15)

| Critério | Pontos | Status | Evidência |
|---|---|---|---|
| Reconciliação `GET /v2/transactions/:id` | 4 / 4 | ✓ | {{`reconcile()` em `pix.ts:60`}} |
| Endpoint admin de reconciliação | 2 / 2 | ✓ | {{path da rota admin}} |
| Job noturno documentado | {{X}} / 3 | {{✓/✗}} | {{`README_PAGOU_PIX.md` seção cron}} |
| Testes passando | 4 / 4 | ✓ | {{`TEST_REPORT.md`}} |
| Logs estruturados | 2 / 2 | ✓ | {{JSON loggable verificado}} |

---

## Para chegar a 95+

- [ ] {{ponto que ficou parcial — ex.: implementar job noturno como cron real em vez de manual}}
- [ ] {{outro ponto — ex.: aumentar cobertura de testes para >90%}}

## Para chegar a 100

- [ ] {{ponto crítico restante}}
- [ ] {{ponto crítico restante}}

---

## Notas

- {{Qualquer contexto importante: ex. "score < 95 por falta de cron real em ambiente serverless — usar Inngest scheduled function quando upgrade do plano permitir"}}
- {{Quando re-avaliar: ex. "rodar scoring novamente após 1 semana em produção"}}
