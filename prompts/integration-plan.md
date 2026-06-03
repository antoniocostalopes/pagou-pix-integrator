# Prompt — Integration Plan (Fase 2 — Human Approval Gate)

**Objetivo:** apresentar plano explícito de mudanças e obter aprovação **antes** de modificar qualquer arquivo.

## Estrutura do plano

Use o template `templates/PAGOU_PIX_INTEGRATION_PLAN.md` para gerar o arquivo. Salvar na raiz do projeto-alvo (não dentro da Skill).

## Conteúdo obrigatório

### 1. Resumo da descoberta

```markdown
**Framework:** Next.js 14 (App Router)
**Linguagem:** TypeScript
**Banco:** PostgreSQL (via Prisma)
**Auth:** NextAuth
**Test runner:** Vitest
**Padrão:** layered, services em src/lib
**Gateway existente:** nenhum
**Modelo de pedido:** prisma.order
**Status atual de pedido:** Order.status (enum)
**Modo de confirmação escolhido:** webhook (default)  ← OU "polling" se utilizador optou
```

### 1.b Consequências do modo escolhido

Incluir uma das duas secções conforme escolha:

**Se modo = `webhook`:**

> O caminho de confirmação será webhook (recomendado). A Skill vai gerar o endpoint `/api/webhooks/pagou`, registar `PAGOU_WEBHOOK_SECRET` no `.env`, e criar um job de reconciliação **horário** como fallback. O utilizador precisa, após o deploy, registar a URL pública no painel da Pagou e colar o secret HMAC no `.env`.

**Se modo = `polling`:**

> O caminho de confirmação será polling backend. A Skill vai gerar um **background poller** que pergunta `GET /v2/transactions/{id}` cada 30s desde a criação até estado terminal ou expiração do PIX, e um **job de reconciliação a cada 15 minutos** que apanha estados pós-terminal (`refunded`, `chargedback`). O endpoint de webhook continua a ser gerado mas não precisa ser registado na Pagou. Limitações conhecidas: latência de confirmação ≈ 30s, custo de API maior, risco de perder eventos tardios se o job de reconciliação falhar.

### 2. Arquivos a CRIAR (com path completo a partir da raiz)

```
+ src/lib/pagou/client.ts
+ src/lib/pagou/pix.ts
+ src/lib/pagou/status.ts
+ app/api/pagou/pix/route.ts
+ app/api/webhooks/pagou/route.ts
+ prisma/migrations/20260602000000_add_pagou_pix/migration.sql
+ tests/pagou/pix.test.ts
+ tests/pagou/webhook.test.ts
+ tests/pagou/e2e.test.ts
+ PAGOU_PIX_INTEGRATION_PLAN.md
+ PAGOU_PIX_INTEGRATION_REPORT.md (gerado depois)
+ PAGOU_PIX_INTEGRATION_SCORE.md (gerado depois)
+ README_PAGOU_PIX.md
+ TEST_REPORT.md (gerado depois)
```

### 3. Arquivos a MODIFICAR

```
M .env.example                  ← adicionar PAGOU_API_KEY=, PAGOU_ENV=, etc.
M prisma/schema.prisma          ← adicionar 2 models
M README.md                     ← seção "PIX via Pagou"
M src/lib/orders/markPaid.ts    ← se já existe lógica de "marcar pago", adicionar hook do PIX
```

Cada arquivo modificado deve trazer **trecho exato** ou descrição precisa da mudança.

### 4. Mudanças na base de dados

Migração SQL completa, exibida no plano. Nunca surpreender o usuário com schema novo após aprovação.

### 5. Endpoints expostos

```
POST /api/pagou/pix
  Auth: sessão NextAuth do projeto
  Body: { orderId: string }
  Resp: { transactionId, status, pixQrCode, pixCode }

POST /api/webhooks/pagou
  Auth: pública (Pagou chama)
  Body: payload Pagou (evento de transação)
  Resp: { received: true }
```

### 6. Webhook a registrar (só em modo webhook)

```
URL pública: https://app.exemplo.com/api/webhooks/pagou
Eventos: transaction.* (ao menos transaction.paid, transaction.cancelled, transaction.refunded)
```

Documentar que o registro deve ser feito **na dashboard Pagou** após o deploy. Não é a Skill que registra automaticamente (não está no escopo da OpenAPI pública).

**Em modo polling:** esta secção desaparece do plano. O endpoint `/api/webhooks/pagou` continua a ser gerado mas o utilizador não precisa de registar nada.

### 6.b Background poller (só em modo polling)

```
Job: PagouPixPoller
Frequência: cada 30s, por transação, desde criação até estado terminal ou expiração
Onde corre: depende do stack (Vercel Cron, Laravel Schedule, wp-cron, etc.)
Endpoint chamado: GET https://{api-sandbox|api}.pagou.ai/v2/transactions/{id}
```

### 7. Job de reconciliação (gerado em ambos os modos)

```
Frequência: horário em modo webhook, cada 15 min em modo polling
Função: apanhar eventos pós-terminal (refunded, chargedback) que o caminho principal pode ter perdido
```

### 8. Variáveis de ambiente novas

```
PAGOU_API_KEY=
PAGOU_ENV=sandbox
PAGOU_CONFIRMATION_MODE=webhook       # ou "polling"
PAGOU_WEBHOOK_SECRET=                  # só relevante em modo webhook (preencher após registar webhook na Pagou)
PUBLIC_APP_URL=https://app.exemplo.com # só relevante em modo webhook
```

**Nota:** `PAGOU_API_URL` **não é variável de ambiente** — é derivado pelo cliente HTTP a partir de `PAGOU_ENV`.

## Pergunta final

Após mostrar o plano, sempre:

> **Posso prosseguir com este plano? (sim / não / ajustar)**

Aceitar:

- ✓ "sim" / "ok" / "prossegue" / "vai" / "go" → avançar para fase 3
- ✗ "não" → encerrar com mensagem amigável
- "ajustar" / "muda X" → ouvir, atualizar o plano, perguntar de novo

**Nunca** começar a implementação sem resposta afirmativa explícita. Silêncio ≠ aprovação.

## Regras

- O plano deve ser **completo** — qualquer arquivo criado/modificado fora dele é violação
- Trazer estimativa de impacto: "X linhas adicionadas, Y arquivos modificados, 2 tabelas novas"
- Se o usuário aprovar e durante a implementação surgir necessidade de criar/modificar algo fora do plano, **parar e pedir nova aprovação para a mudança específica**
