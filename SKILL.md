---
name: pagou-pix-integrator
description: Analisa projetos existentes (Next.js, Laravel, WordPress, WooCommerce ou genéricos) e implementa uma integração PIX completa via Pagou.ai — cliente, serviço, endpoint, webhook com deduplicação por event_id, reconciliação, testes e relatório com score. Invocação canónica via slash command `/pagou-pix-integrator`. Também responde quando o utilizador pedir em linguagem natural para "integrar PIX", "adicionar Pagou", "implementar pagamento PIX", "webhook Pagou" ou similar num projeto existente.
---

# Pagou PIX Integrator

Skill autônoma para integração PIX em projetos existentes utilizando a plataforma **Pagou.ai**.

## Versão

3.0.1

## Escopo

Esta Skill foca exclusivamente em **PIX (pay-in)**. Cobre:

- Criação de cobrança PIX (`POST /v2/transactions` com `method: "pix"`)
- Recepção, validação, persistência e deduplicação de webhooks
- Reconciliação por `GET /v2/transactions/{id}`
- Testes (unit, integração, webhook, e2e)
- Auditoria de segurança e score técnico

Pix Out (transfers) e Subscriptions estão documentados em `KNOWLEDGE.md` para contexto, mas não são implementados por padrão.

## Fluxo obrigatório (imutável)

```
1. Descobrir   → analisar projeto, framework, DB, ORM, auth, checkout
2. Confirmar   → Human Approval Gate com lista de mudanças
3. Implementar → cliente, serviço, endpoint, webhook, persistência
4. Testar      → unit + integration + webhook + e2e
5. Validar     → checklists de segurança, webhook, reconciliação, produção
6. Pontuar     → score 0–100 com classificação
```

**É proibido inverter esta ordem.** Implementar antes de descobrir, ou pontuar antes de validar, viola o contrato da Skill.

## Perguntas permitidas

Apenas os 4 dados abaixo podem ser solicitados ao usuário:

| Pergunta | Razão (impossível inferir) |
|---|---|
| `PAGOU_API_KEY` | Segredo — não pode estar no repositório |
| Modo de confirmação de pagamento | `webhook` (recomendado, default) ou `polling` (opt-out, mais simples) |
| URL pública do projeto | Necessária para registrar webhook na Pagou (só se modo = webhook) |
| Status internos desejados | Mapeamento de domínio (ex.: `paid` → `aprovado`, `confirmado`) |

**Tudo o resto deve ser descoberto.** Framework, banco, ORM, sistema de auth, fluxo de checkout, tabela principal, padrão de pastas — nada disso pode ser perguntado.

### Apenas produção (desde v3.0.0)

A Skill chama **sempre** `https://api.pagou.ai` (produção). Não suporta sandbox.

- **Não há pergunta de ambiente** — não existe `PAGOU_ENV`.
- O cliente HTTP gerado tem o URL hardcoded — não é configurável por env var.
- Para desenvolvimento local sem tocar em produção, usar `tools/pagou-mock/` que está incluído no repo da Skill (servidor Node que simula a API v2 da Pagou com webhooks HMAC válidos, zero dependências, ideal para CI e dev).
- Testes unit + integration + webhook devem usar mock HTTP (vitest/msw em Node, `Http::fake()` em Laravel, etc.) — nunca atingem a Pagou real.

### Modo de confirmação — webhook vs polling

A partir da versão 2.0.0 a Skill suporta **dois modos** de confirmação:

- **`webhook` (default, recomendado)** — evento `transaction.paid` chega em tempo real. Robusto contra cliente fechar o browser, chargebacks tardios, e refunds manuais. Requer URL pública + registo no painel Pagou.
- **`polling`** — sem URL pública, sem registo no painel. Background poller pergunta `GET /v2/transactions/{id}` periodicamente até estado terminal. Job de reconciliação roda em ciclo curto. Simplifica setup; perde eventos tardios e tem latência maior.

O endpoint de webhook **é sempre gerado em ambos os modos** — em `polling` fica disponível mas não registado, permitindo upgrade futuro sem regenerar código.

## Comportamentos proibidos

- Perguntar informação inferível do projeto
- Modificar ficheiros antes de aprovação explícita (Human Approval Gate)
- Deduplicar webhooks por `data.id` (id da transação) — só `event_id` (id de topo)
- Expor `PAGOU_API_KEY` no frontend, browser, código cliente, repositório ou logs
- Confirmar pagamento a partir de sucesso no browser (apenas via webhook, polling backend ou GET de reconciliação — nunca do retorno síncrono do POST de criação)
- Tratar valores em reais — Pagou v2 trabalha em **centavos**
- Inventar endpoints, campos ou status não documentados na OpenAPI da Pagou

## Pontos de entrada

| Ficheiro | Quando ler |
|---|---|
| `CLAUDE.md` | Sempre — regras de execução da Skill |
| `KNOWLEDGE.md` | Antes de gerar qualquer código — verdade sobre a API Pagou |
| `prompts/project-discovery.md` | Início — fase 1 |
| `prompts/architecture-discovery.md` | Fase 1 (após detectar framework) |
| `prompts/missing-data.md` | Fim da fase 1 — só pede o que falta |
| `prompts/integration-plan.md` | Fase 2 — Human Approval Gate |
| `prompts/pix-integration.md` | Fase 3 — implementação PIX |
| `prompts/webhook-integration.md` | Fase 3 — webhook + dedupe |
| `prompts/reconciliation.md` | Fase 3 — recuperação por GET |
| `prompts/validation.md` | Fase 5 — checklists |
| `prompts/scoring.md` | Fase 6 — cálculo do score |
| `frameworks/*.md` | Após detectar framework no projeto |
| `templates/*.md` | Geração dos relatórios obrigatórios |
| `checklists/*.md` | Validação por categoria |
| `docs/*.md` | Referência interna sobre arquitetura e algoritmo |

## Relatórios obrigatórios

Ao final, gerar no projeto-alvo:

1. `PAGOU_PIX_INTEGRATION_PLAN.md` — gerado **antes** da implementação (Approval Gate)
2. `PAGOU_PIX_INTEGRATION_REPORT.md` — após implementação
3. `PAGOU_PIX_INTEGRATION_SCORE.md` — score 0–100 com classificação
4. `README_PAGOU_PIX.md` — instruções operacionais para o time
5. `TEST_REPORT.md` — resultados dos testes executados

## Classificação

| Faixa | Classificação |
|---|---|
| 95–100 | Enterprise Ready |
| 90–94 | Production Ready |
| 80–89 | Minor Improvements |
| 70–79 | Needs Review |
| 0–69 | Not Ready |

Score abaixo de 90 **não deve ir para produção** sem revisão humana.
