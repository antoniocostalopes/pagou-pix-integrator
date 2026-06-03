# PAGOU_PIX_INTEGRATION_PLAN

> Plano gerado **antes** da implementação. Requer aprovação humana explícita.
> Preencher cada `{{...}}` com base na descoberta do projeto.

## 1. Resumo da descoberta

| Campo | Valor |
|---|---|
| Projeto | {{nome do repositório}} |
| Framework | {{ex.: Next.js 14 App Router}} |
| Linguagem | {{ex.: TypeScript}} |
| Banco de dados | {{ex.: PostgreSQL 16}} |
| ORM | {{ex.: Prisma}} |
| Autenticação | {{ex.: NextAuth}} |
| Padrão arquitetural | {{ex.: layered services em src/lib}} |
| Test runner | {{ex.: Vitest}} |
| Gateway atual | {{nenhum / Stripe / MP / etc.}} |
| Modelo de pedido | {{ex.: prisma.order}} |
| Status atual de pedido | {{ex.: Order.status (enum interno)}} |
| API Pagou alvo | `https://api.pagou.ai` (constante; Skill v3+ não suporta sandbox) |
| Modo de confirmação | {{webhook (default) | polling}} |
| URL pública | {{ex.: https://app.exemplo.com}} (só relevante se modo = webhook) |

## 2. Mapeamento de status

| Pagou | Status interno |
|---|---|
| `pending` | `{{aguardando_pagamento}}` |
| `paid` | `{{pago}}` |
| `expired` | `{{expirado}}` |
| `canceled` | `{{cancelado}}` |
| `refused` | `{{recusado}}` |
| `refunded` | `{{estornado}}` |
| `partially_refunded` | `{{estornado_parcial}}` |
| `chargedback` | `{{chargeback}}` |

## 3. Arquivos a criar

```diff
+ {{caminho/arquivo1}}
+ {{caminho/arquivo2}}
+ {{caminho/arquivo3}}
...
```

## 4. Arquivos a modificar

| Arquivo | Mudança |
|---|---|
| `.env.example` | Adicionar `PAGOU_API_KEY`, `PAGOU_CONFIRMATION_MODE`, `PAGOU_WEBHOOK_SECRET` (se webhook), `PUBLIC_APP_URL` (se webhook) — **sem** `PAGOU_ENV` nem `PAGOU_BASE_URL` |
| `{{schema/migrations}}` | 2 novas tabelas |
| `README.md` | Seção "PIX via Pagou" |
| `{{outro}}` | {{descrição}} |

## 5. Mudanças na base de dados

### Tabela `pagou_pix_transactions`

```sql
{{DDL completa conforme adapter de framework}}
```

### Tabela `pagou_webhook_events`

```sql
{{DDL completa}}
```

## 6. Endpoints expostos

| Método | Path | Auth | Descrição |
|---|---|---|---|
| POST | `{{/api/pagou/pix}}` | sessão | Cria cobrança PIX |
| POST | `{{/api/webhooks/pagou}}` | pública | Webhook Pagou |
| POST | `{{/admin/pagou/reconcile/:id}}` | admin | Reconciliação manual |

## 7. Webhook a registrar na Pagou

**Se modo = `webhook`:**

```
URL: {{https://app.exemplo.com/api/webhooks/pagou}}
Eventos: transaction.created, transaction.pending, transaction.paid,
         transaction.cancelled, transaction.refunded, transaction.chargedback
```

> Registro feito manualmente no painel Pagou após o deploy.
> Após registar, copiar o `PAGOU_WEBHOOK_SECRET` do painel para o `.env`.

**Se modo = `polling`:** ignorar esta secção. O endpoint `/api/webhooks/pagou` continua a ser gerado mas o utilizador não precisa de registar nada no painel. O caminho de confirmação é polling backend (ver secção 7.b).

## 7.b Background poller (só em modo polling)

```
Job: pagou:poll
Frequência: cada 1 minuto (granularidade mínima da maioria dos schedulers)
Janela: transações em status pending/created criadas na última 1h
Endpoint: GET https://api.pagou.ai/v2/transactions/{id}
```

## 7.c Job de reconciliação (gerado em ambos os modos)

```
Frequência: horária em modo webhook, cada 15 min em modo polling
Janela: transações terminais criadas nos últimos 30 dias
Propaga: refunded, partially_refunded, chargedback
```

## 8. Variáveis de ambiente novas

```bash
PAGOU_API_KEY=                              # secret — backend only — chave de PRODUÇÃO
PAGOU_CONFIRMATION_MODE={{webhook|polling}} # decide caminho principal de confirmação
PAGOU_WEBHOOK_SECRET=                       # só relevante em modo webhook (preencher após registar)
PUBLIC_APP_URL={{https://app.exemplo.com}}  # só relevante em modo webhook
```

**Nota:** `PAGOU_API_URL` **não é variável de ambiente**. É constante hardcoded `https://api.pagou.ai` no cliente HTTP. Skill v3+ não suporta sandbox nem override por env var. Para dev local sem cobranças reais, usar `tools/pagou-mock/` no repo da Skill.

## 9. Testes a gerar

| Tipo | Arquivo | Cobertura |
|---|---|---|
| Unit | `{{tests/pagou/status.test.ts}}` | mapStatus |
| Unit | `{{tests/pagou/amount.test.ts}}` | conversão centavos |
| Integration | `{{tests/pagou/client.test.ts}}` | wrapper HTTP (mock) |
| Webhook | `{{tests/pagou/webhook.test.ts}}` | dedupe + processing |
| E2E | `{{tests/pagou/e2e.test.ts}}` | fluxo completo |

## 10. Impacto

- {{X linhas adicionadas}}
- {{Y arquivos criados, Z arquivos modificados}}
- {{2 tabelas novas}}
- {{nenhuma migration destrutiva}}

## 11. Riscos identificados

- {{ex.: projeto não tem fila — webhook processado inline; documentar limite < 5s}}
- {{ex.: não há logger estruturado — Skill usa o existente do framework}}

---

## Aprovação

> Posso prosseguir com este plano?

- [ ] **Sim** — implementar conforme acima
- [ ] **Não** — encerrar
- [ ] **Ajustar** — descreva: _______________

Aprovado por: ____________________ em ____ / ____ / ______
