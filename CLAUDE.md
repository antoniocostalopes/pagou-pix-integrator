# CLAUDE.md — Instruções de execução da Skill Pagou PIX Integrator

Estas instruções são **carregadas sempre** que a Skill estiver ativa. Sobrescrevem comportamento padrão do Claude para esta tarefa específica.

## Regra mestra

Siga sempre, e nunca inverta, a sequência:

```
Descobrir → Confirmar → Implementar → Testar → Validar → Pontuar
```

Cada fase tem critérios de saída. Não avance até cumpri-los.

---

## Fase 1 — Descobrir (silencioso)

**Não fale com o usuário durante esta fase além de avisar "Analisando o projeto…".**

Leia, sem perguntar:

1. `package.json`, `composer.json`, `wp-config.php`, `requirements.txt`, `pyproject.toml`, `go.mod`, `Gemfile`
2. `next.config.js|ts|mjs`, `nuxt.config.*`, `vite.config.*`, `artisan`, `manage.py`, `app.py`, `main.go`
3. Estrutura de pastas: `src/`, `app/`, `pages/`, `routes/`, `controllers/`, `services/`, `repositories/`, `models/`, `migrations/`, `database/`
4. Arquivos de rota e endpoints: `routes/web.php`, `routes/api.php`, `app/api/**`, `pages/api/**`, `urls.py`, `routes.rb`
5. ORM/Driver: Prisma (`schema.prisma`), Eloquent (`app/Models`), TypeORM, Sequelize, Drizzle, Django ORM, ActiveRecord
6. Sistema de auth: NextAuth, Passport, Laravel Sanctum/Passport, Django auth, Devise, custom JWT
7. Variáveis de ambiente: `.env`, `.env.example`, `.env.local`
8. Fluxo de checkout existente: procurar por `checkout`, `order`, `cart`, `pedido`, `compra`, `payment`
9. Tabela principal de transação/pedido: `orders`, `pedidos`, `transactions`, `payments`, `subscriptions`, `wp_posts` (WooCommerce)
10. Pasta de testes: `tests/`, `__tests__/`, `spec/`, `test/`

**Saída desta fase** — você deve saber:

- Framework e versão
- Linguagem
- Banco de dados (Postgres, MySQL, SQLite, MariaDB, etc.)
- ORM ou query builder
- Sistema de autenticação
- Onde fica o checkout/pedido
- Modelo/tabela onde a transação PIX será associada
- Convenção de testes do projeto
- Padrão de organização (MVC, hexagonal, modules, etc.)

**Critério de saída:** Você tem ≥ 90% do contexto. Os únicos buracos restantes são os 5 perguntáveis (PAGOU_API_KEY, env, URL pública, status internos, modo de confirmação).

---

## Fase 2 — Confirmar (Human Approval Gate)

Antes de **qualquer** modificação no projeto, gere `PAGOU_PIX_INTEGRATION_PLAN.md` a partir de `templates/PAGOU_PIX_INTEGRATION_PLAN.md` contendo:

- Resumo da descoberta (framework, DB, ORM, etc.)
- **Modo de confirmação escolhido** (`webhook` ou `polling`) e suas consequências
- **Lista exata** de arquivos a criar
- **Lista exata** de arquivos a modificar (com trecho/intenção)
- Mudanças na base de dados (migration completa)
- Endpoints a expor (path, método, auth)
- Webhook a registrar (path, payload esperado) — só se modo = webhook
- Job de polling + reconciliação curta — só se modo = polling
- Variáveis de ambiente novas

Em seguida, **pergunte os 5 dados permitidos** usando `prompts/missing-data.md`, e solicite aprovação explícita:

> "Posso prosseguir com este plano? (sim/não/ajustar)"

**Critério de saída:** Aprovação explícita do usuário. Sem isto, pare.

---

## Fase 3 — Implementar

Use o adapter de framework correspondente em `frameworks/`:

- Next.js (App Router ou Pages) → `frameworks/nextjs.md`
- Laravel → `frameworks/laravel.md`
- WordPress (sem WooCommerce) → `frameworks/wordpress.md`
- WooCommerce → `frameworks/woocommerce.md`
- Qualquer outro → `frameworks/generic.md`

Implemente nesta ordem:

1. **Configuração** (env vars, config file — incluir `PAGOU_CONFIRMATION_MODE` com valor do utilizador)
2. **Migração de DB** (tabela `pagou_pix_transactions` + tabela `pagou_webhook_events` para idempotência — esta última necessária em ambos os modos)
3. **Cliente Pagou** (wrapper HTTP com auth, base URL por ambiente, tratamento de erros)
4. **Serviço PIX** (criar cobrança, consultar status)
5. **Endpoint público** (criar cobrança PIX para o frontend)
6. **Endpoint de webhook** (`POST /webhooks/pagou`) — gerado em ambos os modos; em modo `polling` fica disponível mas o utilizador não regista no painel
7. **Background poller curto** — gerado **só se modo = polling**: pergunta `GET /v2/transactions/{id}` cada 30s até estado terminal ou expiração do PIX
8. **Job de reconciliação** — sempre gerado; frequência depende do modo (modo webhook = horário; modo polling = a cada 15 min para apanhar eventos tardios como chargedback)
9. **Status mapping** (Pagou → status interno do projeto)
10. **Tratamento de erros** + logging seguro (sem segredos)

**Regras inegociáveis durante a implementação:**

- `PAGOU_API_KEY` lida **apenas no servidor** via `process.env`/equivalente
- Amounts em **centavos** (multiplicar BRL por 100)
- Sempre incluir `external_ref` (use o id interno do pedido)
- Webhook ACK rápido: responder `{"received": true}` com status 200 antes de processar lógica pesada (idealmente enfileirar)
- Deduplicar por **`event.id`** (top-level), **nunca** `data.id`
- Confirmar pedido só por webhook, polling backend ou GET de reconciliação — **nunca** pelo retorno síncrono do POST de criação ou por polling do browser à API Pagou
- Em modo `polling`: o frontend continua a fazer polling **a um endpoint interno** (`/api/orders/:id/status`), nunca à Pagou directamente. A própria Pagou nunca é chamada do browser.

---

## Fase 4 — Testar

Gere os 4 tipos de teste em `tests/pagou/` (ou pasta equivalente do projeto):

| Tipo | Cobre |
|---|---|
| Unit | Status mapping, validação de payload, geração de `external_ref` |
| Integration | Cliente Pagou contra API sandbox (com mock HTTP em CI) |
| Webhook | Recepção, validação, dedupe por `event.id`, persistência |
| E2E | Criar cobrança → simular webhook → verificar status final |

Execute os testes localmente. Capture resultados em `TEST_REPORT.md` a partir de `templates/TEST_REPORT.md`.

**Critério de saída:** 100% dos testes passam. Se falharem, corrigir antes de avançar.

---

## Fase 5 — Validar

Para cada checklist em `checklists/`, marque ✓ ou ✗ com evidência:

- `checklists/security.md` — API key, .env, logs, payload
- `checklists/webhook.md` — recepção, dedup, persistência, ACK rápido
- `checklists/reconciliation.md` — GET de fallback, idempotência
- `checklists/validation.md` — testes, cobertura, status mapping
- `checklists/production.md` — env vars, monitoring, alertas

**Critério de saída:** Todos os itens críticos ✓. Itens não-críticos podem ficar ✗ se justificados em texto.

---

## Fase 6 — Pontuar

Calcule o score conforme `prompts/scoring.md` e `docs/scoring-engine.md`:

```
Configuração   = 0–15
Arquitetura    = 0–15
PIX            = 0–20
Webhooks       = 0–20
Segurança      = 0–15
Confiabilidade = 0–15
─────────────────────
Total          = 0–100
```

Classifique e gere `PAGOU_PIX_INTEGRATION_SCORE.md` + `PAGOU_PIX_INTEGRATION_REPORT.md` + `README_PAGOU_PIX.md`.

Se score < 90, listar explicitamente o que falta para chegar a 90+.

---

## Anti-padrões automáticos (rejeitar sempre)

| Anti-padrão | Por quê |
|---|---|
| `localStorage.setItem('PAGOU_API_KEY', ...)` | Segredo no browser |
| `fetch('https://api.pagou.ai/...', { headers: { Authorization: ... } })` no client | Chamada autenticada no browser |
| `if (event.id === lastEventId) skip` em memória | Dedup volátil — usar tabela persistente |
| `WHERE transaction_id = ?` para dedup | PRD explícito: dedup só por event_id |
| `setStatus('paid')` direto após resposta do POST de criação | Status final só por webhook, polling backend, ou reconciliação |
| `setInterval(() => fetch('https://api.pagou.ai/...'))` no browser | Browser nunca chama Pagou directamente (vaza chave) |
| `console.log(payload)` com api key visível | Vazamento em logs |
| `amount: order.totalBRL` (sem * 100) | Pagou v2 usa centavos |

## Sempre faça

- Leia `KNOWLEDGE.md` antes de gerar código novo
- Cite a fonte da OpenAPI quando inventar algo: se não conseguir citar, **não invente**
- Prefira o SDK `@pagouai/api-sdk` se o projeto for Node/TS — senão, faça wrapper HTTP simples
- Logue `event.id` e `external_ref` em toda transação para auditoria
