<div align="center">

# 💸 Pagou PIX Integrator

### Plugin para Claude Code que integra PIX via Pagou.ai em qualquer projeto existente — com descoberta automática, aprovação humana, testes, validação e score técnico.

[![Version](https://img.shields.io/badge/version-1.2.0-blue.svg?style=for-the-badge)](./CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg?style=for-the-badge)](./LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-D97706?style=for-the-badge&logo=anthropic&logoColor=white)](https://claude.com/claude-code)
[![PT-BR](https://img.shields.io/badge/lang-PT--BR-009C3B?style=for-the-badge)](#)

[![Next.js](https://img.shields.io/badge/Next.js-000?style=flat&logo=nextdotjs&logoColor=white)](./frameworks/nextjs.md)
[![Laravel](https://img.shields.io/badge/Laravel-FF2D20?style=flat&logo=laravel&logoColor=white)](./frameworks/laravel.md)
[![WordPress](https://img.shields.io/badge/WordPress-21759B?style=flat&logo=wordpress&logoColor=white)](./frameworks/wordpress.md)
[![WooCommerce](https://img.shields.io/badge/WooCommerce-7F54B3?style=flat&logo=woocommerce&logoColor=white)](./frameworks/woocommerce.md)
[![Generic](https://img.shields.io/badge/+%20any%20stack-555?style=flat)](./frameworks/generic.md)

[**🚀 Instalação**](#-instalação) • [**⚙️ Como funciona**](#️-como-funciona) • [**🧰 Frameworks**](#-frameworks-suportados) • [**📊 Sistema de score**](#-sistema-de-score) • [**📚 Documentação**](#-documentação)

</div>

---

## ⚡ Quick start

Um único comando no terminal:

```bash
# macOS / Linux / WSL
git clone https://github.com/antoniocostalopes/pagou-pix-integrator.git ~/.claude/skills/pagou-pix-integrator
```

```powershell
# Windows (PowerShell)
git clone https://github.com/antoniocostalopes/pagou-pix-integrator.git "$env:USERPROFILE\.claude\skills\pagou-pix-integrator"
```

Reinicia o Claude Code, depois em qualquer projeto:

```text
/pagou-pix-integrator
```

> 💡 Preferes o sistema nativo de plugins (com `enable`/`disable`/`update` via `/plugin`)? Vê o [caminho alternativo](#caminho-alternativo--via-plugin-marketplace).

---

## 🎯 O que é

**Pagou PIX Integrator** é um [plugin do Claude Code](https://claude.com/claude-code) que **analisa o seu projeto existente** e implementa uma integração PIX completa via [Pagou.ai](https://developer.pagou.ai), seguindo boas práticas de arquitetura, segurança e auditoria.

Em vez de leres documentação, copiares snippets e adaptares para o teu stack, invocas a Skill: ela descobre o projeto, propõe um plano, esperas pela tua aprovação, e ela entrega:

- ✅ **Cliente HTTP autenticado** para a API Pagou v2
- ✅ **Endpoint público** de criação de cobrança PIX
- ✅ **Webhook handler** com **verificação HMAC-SHA256**, deduplicação por `event.id` e ACK rápido
- ✅ **Endpoints admin** para **cancelar PIX pendente** e **estornar** (total ou parcial)
- ✅ **Migrations** para `pagou_pix_transactions` e `pagou_webhook_events` com constraints UNIQUE
- ✅ **Serviço de reconciliação** via `GET /v2/transactions/:id` com job noturno e endpoint admin
- ✅ **Frontend snippets** (React hook + componente, Blade + Alpine, padrão universal) com prefixo `data:image/png;base64,` correto no QR
- ✅ **Testes** unit + integration + webhook + e2e
- ✅ **Observabilidade** — 15 métricas Prometheus/OTel, 8 alert rules, dashboard Grafana
- ✅ **5 relatórios obrigatórios** (PLAN antes, REPORT/SCORE/README/TEST depois)
- ✅ **Score técnico 0–100** com classificação determinística

---

## ✨ Features

| | |
|---|---|
| 🔍 **Descoberta automática** | Analisa `package.json`, `composer.json`, `wp-config.php`, ORM, rotas, auth, fluxo de checkout — **sem perguntar** |
| 🤝 **Human Approval Gate** | Antes de modificar qualquer arquivo, apresenta plano explícito com lista de mudanças |
| ❓ **Só 4 perguntas** | API key, ambiente, URL pública, status internos — tudo o resto é inferido |
| 🔐 **HMAC nos webhooks** | `HMAC-SHA256` no header `X-Pagou-Signature` com comparação em tempo constante; fail-closed em produção |
| 🛡️ **Segurança built-in** | API key apenas backend, valores em centavos, sem segredos em logs ou commits |
| 🔁 **Idempotência tripla** | Upsert por `external_ref`, UNIQUE em `event_id`, no-regress em status terminais |
| ⚡ **Webhook resiliente** | ACK em < 1s, processamento assíncrono em fila, dedup por id de evento |
| 💸 **Cancel + Refund** | Endpoints admin para cancelar PIX pendente e estornar (total ou parcial) |
| 🩹 **Reconciliação** | Job noturno + endpoint admin que recupera estado via GET |
| 🎨 **Frontend pronto** | React hook + componente, Blade component, padrão universal — todos com prefixo MIME no QR |
| 📈 **Observabilidade** | 15 métricas Prometheus/OTel, 8 alert rules, dashboard Grafana pré-configurado |
| 🧪 **Mock + tester locais** | Servidor mock da API Pagou + script de webhook tester com HMAC válido (em `tools/`) |
| 📊 **Score determinístico** | 6 categorias com pesos fixos, total 0–100 com classificação |
| 🌐 **5 stacks suportados** | Next.js, Laravel, WordPress, WooCommerce, + adapter genérico |
| 📝 **PT-BR** | Toda a documentação e relatórios em português brasileiro |

---

## ⚙️ Como funciona

A Skill segue um **fluxo imutável de 6 fases**. Nunca inverte a ordem.

```
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│ 1. Descobrir  │───►│ 2. Confirmar  │───►│ 3. Implementar│
│ (silencioso)  │    │ Human Approval│    │ (código real) │
└───────────────┘    └───────────────┘    └───────────────┘
                                                  │
                                                  ▼
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│ 6. Pontuar    │◄───│ 5. Validar    │◄───│ 4. Testar     │
│ score 0–100   │    │  checklists   │    │ unit+int+e2e  │
└───────────────┘    └───────────────┘    └───────────────┘
```

| Fase | O que acontece | Sai com |
|---|---|---|
| 1️⃣ **Descobrir** | Lê manifestos, rotas, models, migrations, auth, fluxo de checkout existente | ≥ 90% do contexto; só faltam os 4 perguntáveis |
| 2️⃣ **Confirmar** | Gera `PAGOU_PIX_INTEGRATION_PLAN.md` com lista exata de arquivos a criar/modificar, DDL, endpoints | Aprovação explícita do utilizador |
| 3️⃣ **Implementar** | Aplica o adapter do framework — cliente, serviço, endpoints (criar / cancel / refund / webhook), persistência, frontend | Código pronto a rodar |
| 4️⃣ **Testar** | Gera e executa unit + integration + webhook + e2e (incluindo HMAC e refund) | 100% verdes |
| 5️⃣ **Validar** | Percorre 5 checklists com evidência por item | Todos os críticos ✓ |
| 6️⃣ **Pontuar** | Calcula score 0–100 e gera relatório final | Classificação |

---

## 🚀 Instalação

### Pré-requisitos

- [Claude Code CLI](https://claude.com/claude-code) instalado
- Git no sistema

### Caminho recomendado — `git clone` (1 comando)

#### Windows (PowerShell)

```powershell
git clone https://github.com/antoniocostalopes/pagou-pix-integrator.git "$env:USERPROFILE\.claude\skills\pagou-pix-integrator"
```

#### macOS / Linux / WSL

```bash
git clone https://github.com/antoniocostalopes/pagou-pix-integrator.git ~/.claude/skills/pagou-pix-integrator
```

Reinicia o Claude Code. A skill fica disponível em qualquer projeto. O Claude Code varre `~/.claude/skills/*/SKILL.md` no arranque — o nosso repo tem `SKILL.md` no root com frontmatter YAML válido.

#### Atualizar

```bash
git -C ~/.claude/skills/pagou-pix-integrator pull
```

#### Desinstalar

```bash
# Unix
rm -rf ~/.claude/skills/pagou-pix-integrator

# Windows
Remove-Item -Recurse -Force "$env:USERPROFILE\.claude\skills\pagou-pix-integrator"
```

<a id="caminho-alternativo--via-plugin-marketplace"></a>

### Caminho alternativo — via `/plugin marketplace`

Se preferes o sistema nativo de plugins do Claude Code (com `enable/disable/uninstall/update` integrados):

```text
/plugin marketplace add antoniocostalopes/pagou-pix-integrator
/plugin install pagou-pix-integrator@pagou-pix-integrator
```

São 2 comandos porque o sistema separa **fonte** (marketplace) de **consumo** (plugin) — o mesmo padrão dos plugins oficiais (Figma e outros).

📖 Detalhes completos e troubleshooting em [**`INSTALL.md`**](./INSTALL.md).

---

## 💡 Uso

Dentro de qualquer projeto onde queres adicionar PIX, no Claude Code:

```text
/pagou-pix-integrator
```

Ou simplesmente pede em linguagem natural:

> _"Integra PIX via Pagou.ai neste projeto."_
>
> _"Adiciona um webhook da Pagou e implementa a cobrança PIX."_

A Skill cuida do resto. Só precisas de **4 informações** — tudo o resto é descoberto:

1. 🔑 **`PAGOU_API_KEY`** — chave da tua conta Pagou
2. 🌐 **Ambiente** — sandbox ou produção
3. 🔗 **URL pública** do projeto (para registar o webhook)
4. 🏷️ **Status internos** — como mapear `paid` → `pago` no teu domínio

---

## 🧰 Frameworks suportados

Cada adapter traz **código pronto a copiar**, específico para o stack, com cliente HTTP, serviço, endpoints (criar / cancel / refund / webhook com HMAC), migrations, frontend, e testes.

| | Framework | Adapter | Inclui |
|---|---|---|---|
| ⚫ | **Next.js** (App + Pages Router) | [`frameworks/nextjs.md`](./frameworks/nextjs.md) | Prisma · Vitest · TypeScript · React hook + componente |
| 🔴 | **Laravel** (9, 10, 11) | [`frameworks/laravel.md`](./frameworks/laravel.md) | Eloquent · Jobs · Pest/PHPUnit · Blade + Alpine |
| 🔵 | **WordPress** (6.0+) | [`frameworks/wordpress.md`](./frameworks/wordpress.md) | Plugin · REST API · wp-cron |
| 🟣 | **WooCommerce** (7.0+) | [`frameworks/woocommerce.md`](./frameworks/woocommerce.md) | Gateway WC · HPOS · meta de pedido |
| ⚪ | **Genérico** | [`frameworks/generic.md`](./frameworks/generic.md) | Express, FastAPI, Django, Rails, Go, .NET, … |

Não vês o teu stack? O adapter genérico cobre o **contrato universal** (DDL, pseudocódigo, contratos de endpoint, HMAC verify por linguagem) que adaptas para qualquer linguagem.

---

## 🛡️ Princípios não-negociáveis

Encodados em `CLAUDE.md` e validados em cada checklist:

| 🚫 Anti-padrão | ✅ Como a Skill faz |
|---|---|
| `PAGOU_API_KEY` no browser | Apenas backend, validado por grep negativo |
| Webhook sem verificação | HMAC-SHA256 obrigatório em produção (fail-closed) |
| Dedup por `data.id` (transação) | Dedup por `event.id` (top-level) — uma transação emite N eventos |
| `setStatus('paid')` após sucesso no browser | Estado final **só** via webhook ou GET de reconciliação |
| Valores em reais | Sempre em **centavos** (Pagou v2) — verificado por teste |
| Esquecer `external_ref` | Sempre presente — base de idempotência e reconciliação |
| Webhook handler com lógica pesada inline | ACK rápido `{"received": true}` + processamento assíncrono |
| Retry de `POST` em erro | Reconciliação via `GET`, não retentativa de criação |
| Confirmar refund no POST | Esperar webhook `transaction.refunded` (estorno bancário leva tempo) |
| QR base64 sem prefixo MIME | Sempre `data:image/png;base64,` no `<img src=...>` |

---

## 🏗️ Arquitetura — o que é gerado no seu projeto

```
seu-projeto/
├── src/lib/pagou/                     (ou app/Services/Pagou/, plugins/pagou-pix/, etc.)
│   ├── client.ts                      ← wrapper HTTP autenticado
│   ├── pix.ts                         ← serviço PIX (criar · consultar · cancel · refund)
│   ├── signature.ts                   ← verificação HMAC-SHA256 do webhook
│   └── status.ts                      ← mapeamento Pagou → status interno
│
├── src/hooks/usePagouPix.ts                              ← hook React (criar · polling · estados)
├── src/components/PixCheckout.tsx                        ← QR + copia-e-cola + UX completa
│
├── app/api/pagou/pix/route.ts                            ← endpoint público (criar cobrança)
├── app/api/webhooks/pagou/route.ts                       ← webhook (HMAC + dedup + ACK rápido)
├── app/api/admin/pagou/transactions/[id]/cancel/route.ts ← admin (cancelar PIX pendente)
├── app/api/admin/pagou/transactions/[id]/refund/route.ts ← admin (estornar total/parcial)
├── app/api/metrics/route.ts                              ← Prometheus exposition (opcional)
│
├── prisma/migrations/                 ← 2 tabelas novas
│   └── add_pagou_pix/
│       ├── pagou_pix_transactions     ← UNIQUE external_ref + pagou_transaction_id
│       └── pagou_webhook_events       ← UNIQUE event_id (idempotência)
│
├── tests/pagou/                       ← 6 suítes
│   ├── status.test.ts                 (unit)
│   ├── signature.test.ts              (HMAC verify + replay rejection)
│   ├── client.test.ts                 (integration)
│   ├── webhook.test.ts                (dedup + processing + invalid sig)
│   ├── refund.test.ts                 (total + parcial)
│   └── e2e.test.ts                    (fluxo completo)
│
├── PAGOU_PIX_INTEGRATION_PLAN.md      ← gerado ANTES (approval gate)
├── PAGOU_PIX_INTEGRATION_REPORT.md    ← gerado DEPOIS
├── PAGOU_PIX_INTEGRATION_SCORE.md     ← score 0–100
├── README_PAGOU_PIX.md                ← guia operacional
└── TEST_REPORT.md                     ← resultados dos testes
```

Diagramas detalhados em [`docs/architecture.md`](./docs/architecture.md), [`docs/payment-flow.md`](./docs/payment-flow.md) e [`docs/webhook-flow.md`](./docs/webhook-flow.md).

---

## 📊 Sistema de score

A Skill termina sempre com um score técnico **0–100** calculado deterministicamente.

### Categorias e pesos

| Categoria | Peso |
|---|---|
| ⚙️ Configuração | **15** |
| 🏗️ Arquitetura | **15** |
| 💸 PIX | **20** |
| 📡 Webhooks | **20** |
| 🛡️ Segurança | **15** |
| 🩹 Confiabilidade | **15** |
| **Total** | **100** |

### Classificação

| Faixa | Classificação | Ação |
|---|---|---|
| 🟢 **95–100** | Enterprise Ready | Liberar |
| 🟢 **90–94** | Production Ready | Liberar com monitorização extra |
| 🟡 **80–89** | Minor Improvements | Listar gaps e corrigir antes de prod |
| 🟠 **70–79** | Needs Review | Revisão humana obrigatória |
| 🔴 **0–69** | Not Ready | Não deploy. Re-trabalhar. |

> ⚠️ **Score abaixo de 90 não vai para produção sem revisão humana.**

Algoritmo determinístico em [`docs/scoring-engine.md`](./docs/scoring-engine.md).

---

## 📚 Documentação

### 🧠 Como a Skill pensa

- [`SKILL.md`](./SKILL.md) — contrato e fluxo (frontmatter YAML invocável)
- [`CLAUDE.md`](./CLAUDE.md) — instruções de execução das 6 fases
- [`KNOWLEDGE.md`](./KNOWLEDGE.md) — fonte única da verdade sobre a API Pagou v2

### 🎬 Roteiros executáveis por fase

- [`prompts/project-discovery.md`](./prompts/project-discovery.md)
- [`prompts/architecture-discovery.md`](./prompts/architecture-discovery.md)
- [`prompts/missing-data.md`](./prompts/missing-data.md)
- [`prompts/integration-plan.md`](./prompts/integration-plan.md)
- [`prompts/pix-integration.md`](./prompts/pix-integration.md)
- [`prompts/webhook-integration.md`](./prompts/webhook-integration.md)
- [`prompts/reconciliation.md`](./prompts/reconciliation.md)
- [`prompts/validation.md`](./prompts/validation.md)
- [`prompts/scoring.md`](./prompts/scoring.md)

### 📄 Templates de relatórios

- [`templates/PAGOU_PIX_INTEGRATION_PLAN.md`](./templates/PAGOU_PIX_INTEGRATION_PLAN.md)
- [`templates/PAGOU_PIX_INTEGRATION_REPORT.md`](./templates/PAGOU_PIX_INTEGRATION_REPORT.md)
- [`templates/PAGOU_PIX_INTEGRATION_SCORE.md`](./templates/PAGOU_PIX_INTEGRATION_SCORE.md)
- [`templates/README_PAGOU_PIX.md`](./templates/README_PAGOU_PIX.md)
- [`templates/TEST_REPORT.md`](./templates/TEST_REPORT.md)

### ✅ Checklists de validação

- [`checklists/security.md`](./checklists/security.md)
- [`checklists/webhook.md`](./checklists/webhook.md) — inclui validação HMAC obrigatória
- [`checklists/reconciliation.md`](./checklists/reconciliation.md)
- [`checklists/validation.md`](./checklists/validation.md)
- [`checklists/production.md`](./checklists/production.md)

### 🔬 Referência interna

- [`docs/architecture.md`](./docs/architecture.md) — visão da Skill e do código gerado
- [`docs/payment-flow.md`](./docs/payment-flow.md) — fluxo end-to-end de uma cobrança
- [`docs/webhook-flow.md`](./docs/webhook-flow.md) — handler, job, idempotência
- [`docs/scoring-engine.md`](./docs/scoring-engine.md) — algoritmo determinístico do score

---

## 📈 Observabilidade

Production-ready desde a v1.2.0 — sem trabalho manual:

- [`docs/observability/metrics.md`](./docs/observability/metrics.md) — 15 métricas Prometheus/OTel com snippets para Node, Laravel, Python, Go
- [`docs/observability/prometheus-alerts.yml`](./docs/observability/prometheus-alerts.yml) — 8 regras de alerta prontas (webhook errors, invalid signatures, silence detection, latência, drift de reconciliação)
- [`docs/observability/grafana-dashboard.json`](./docs/observability/grafana-dashboard.json) — dashboard com 9 painéis em 3 linhas (Cobrança · Webhooks · Reconciliação), importável directamente

---

## 🧪 Ferramentas para desenvolvimento

Trabalhar localmente sem depender da API real:

- [`tools/pagou-mock/`](./tools/pagou-mock/) — servidor que simula a API v2 da Pagou (zero dependências, Node 20+). Implementa as 4 rotas (`create`, `get`, `cancel`, `refund`) e dispara webhooks com HMAC válido. Cenários por prefixo de `external_ref`: `expire-`, `refuse-`, `chargeback-`, `slow-`, `silent-`
- [`tools/webhook-tester/`](./tools/webhook-tester/) — script Bash que envia eventos com assinatura HMAC válida para o teu webhook local. Útil para testar dedup e cenários compostos (ex.: refund antes de paid)

---

## 🔗 Referências externas

| | |
|---|---|
| 📘 **Pagou.ai Docs** | https://developer.pagou.ai |
| 📗 **OpenAPI v2** | https://developer.pagou.ai/api-reference/openapi-v2.json |
| 📕 **LLMs Full Docs** | https://developer.pagou.ai/llms-full.txt |
| 📙 **SDK TypeScript** | [`@pagouai/api-sdk`](https://www.npmjs.com/package/@pagouai/api-sdk) |
| 🟪 **Claude Code** | https://claude.com/claude-code |

---

## 🔒 Segurança

Encontraste uma vulnerabilidade? **Não abras issue pública.** Reporta de forma responsável via [GitHub Security Advisories](https://github.com/antoniocostalopes/pagou-pix-integrator/security/advisories/new) ou conforme descrito em [**`SECURITY.md`**](./SECURITY.md). Vemos cada reporte dentro de 48h.

Em escopo: forjar webhooks, vazar segredos, bypass do Approval Gate, SQL injection / XSS / IDOR no código que esta Skill produz. Fora de escopo: vulnerabilidades na API da Pagou propriamente dita.

---

## 🤝 Contribuindo

Contribuições são muito bem-vindas! Lê o [**`CONTRIBUTING.md`**](./CONTRIBUTING.md) e o [**`CODE_OF_CONDUCT.md`**](./CODE_OF_CONDUCT.md) antes de começar.

Resumo:

1. 🍴 Faz fork do repositório
2. 🌿 Cria uma branch: `git checkout -b feat/minha-melhoria`
3. ✏️ Faz as alterações respeitando os princípios em [`CLAUDE.md`](./CLAUDE.md)
4. 📝 Atualiza [`CHANGELOG.md`](./CHANGELOG.md) e bumpa SemVer em `SKILL.md` / `plugin.json` / `marketplace.json` / badge do README
5. 📨 Abre o PR usando o template — o checklist guia-te pelos princípios não-negociáveis

### Áreas onde ajuda é especialmente bem-vinda

- 🌐 Novos adapters de framework (Nuxt, SvelteKit, Symfony, Phoenix, Rails, Django, etc.)
- 🧪 Mais cenários nos testes e2e (refund parcial em sequência, eventos fora de ordem)
- 🌍 Tradução para outras línguas (atualmente PT-BR)
- 🔌 Integração com endpoints adicionais da Pagou (subscriptions, transfers / Pix Out)
- 📊 Variantes do dashboard Grafana (Datadog, New Relic, CloudWatch)

---

## 📅 Changelog

Versão atual: **`1.2.0`** — release de hardening para produção (HMAC + refund/cancel + observabilidade + repo hygiene + DX).

Histórico completo em [`CHANGELOG.md`](./CHANGELOG.md).

---

## 📜 Licença

[MIT](./LICENSE) © 2026 [antoniocostalopes](https://github.com/antoniocostalopes)

---

<div align="center">

### Feito com 💸 para a comunidade brasileira de pagamentos

[**🐛 Reportar bug**](https://github.com/antoniocostalopes/pagou-pix-integrator/issues/new?template=bug_report.md) • [**✨ Sugerir feature**](https://github.com/antoniocostalopes/pagou-pix-integrator/issues/new?template=feature_request.md) • [**🧰 Pedir adapter**](https://github.com/antoniocostalopes/pagou-pix-integrator/issues/new?template=adapter_request.md) • [**⭐ Star no GitHub**](https://github.com/antoniocostalopes/pagou-pix-integrator)

</div>
