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
```

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

### 6. Webhook a registrar

```
URL pública: https://app.exemplo.com/api/webhooks/pagou
Eventos: transaction.* (ao menos transaction.paid, transaction.cancelled, transaction.refunded)
```

Documentar que o registro deve ser feito **na dashboard Pagou** após o deploy. Não é a Skill que registra automaticamente (não está no escopo da OpenAPI pública).

### 7. Variáveis de ambiente novas

```
PAGOU_API_KEY=
PAGOU_ENV=sandbox
PAGOU_BASE_URL=   # opcional
PUBLIC_APP_URL=https://app.exemplo.com
```

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
