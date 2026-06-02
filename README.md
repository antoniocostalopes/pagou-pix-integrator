<div align="center">

# 💸 Pagou PIX Integrator

### Plugin para Claude Code que integra PIX via Pagou.ai em qualquer projeto existente — com descoberta automática, aprovação humana, testes, validação e score técnico.

[![Version](https://img.shields.io/badge/version-1.1.0-blue.svg?style=for-the-badge)](./CHANGELOG.md)
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

Dentro do Claude Code, dois comandos:

```text
/plugin marketplace add antoniocostalopes/pagou-pix-integrator
/plugin install pagou-pix-integrator@pagou-pix-integrator
```

Depois, em qualquer projeto:

```text
/pagou-pix-integrator
```

---

## 🎯 O que é

**Pagou PIX Integrator** é um [plugin do Claude Code](https://claude.com/claude-code) (distribuído via marketplace nativo) que **analisa o seu projeto existente** e implementa uma integração PIX completa via [Pagou.ai](https://developer.pagou.ai), seguindo boas práticas de arquitetura, segurança e auditoria.

Em vez de você ler documentação, copiar snippets, adaptar para o seu stack e torcer para não esquecer nada — você invoca a Skill, ela descobre o projeto, propõe um plano, você aprova, e ela entrega:

- ✅ **Cliente HTTP autenticado** para a API Pagou v2
- ✅ **Endpoint público** de criação de cobrança PIX
- ✅ **Webhook handler** com deduplicação por `event.id` e ACK rápido
- ✅ **Migrations** para `pagou_pix_transactions` e `pagou_webhook_events`
- ✅ **Serviço de reconciliação** via `GET /v2/transactions/:id`
- ✅ **Testes** (unit, integration, webhook, e2e)
- ✅ **5 relatórios obrigatórios** (plano, relatório, score, README operacional, testes)
- ✅ **Score técnico 0–100** com classificação

---

## ✨ Features

| | |
|---|---|
| 🔍 **Descoberta automática** | Analisa `package.json`, `composer.json`, `wp-config.php`, ORM, rotas, auth, fluxo de checkout — **sem perguntar** |
| 🤝 **Human Approval Gate** | Antes de modificar qualquer arquivo, apresenta plano explícito com lista de mudanças |
| ❓ **Só 4 perguntas** | API key, ambiente, URL pública, status internos — tudo o resto é inferido |
| 🛡️ **Segurança built-in** | API key apenas backend, valores em centavos, sem segredos em logs ou commits |
| 🔁 **Idempotência tripla** | Upsert por `external_ref`, UNIQUE em `event_id`, no-regress em status terminais |
| ⚡ **Webhook resiliente** | ACK em < 1s, processamento assíncrono em fila, dedup por id de evento |
| 🩹 **Reconciliação** | Job noturno + endpoint admin que recupera estado via GET |
| 📊 **Score determinístico** | 6 categorias com pesos fixos, total 0–100 com classificação |
| 🌐 **5 stacks suportados** | Next.js, Laravel, WordPress, WooCommerce, + adapter genérico |
| 📝 **PT-BR** | Toda a documentação e relatórios em português brasileiro |

---

## ⚙️ Como funciona

A Skill segue um **fluxo imutável de 6 fases**. Nunca inverte a ordem.

```
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│ 1. Descobrir  │───►│ 2. Confirmar  │───►│ 3. Implementar│
│   (silencioso)│    │ Human Approval│    │ (código real) │
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
| 1️⃣ **Descobrir** | Lê manifestos, rotas, models, migrations, auth, fluxo de checkout existente | ≥ 90% do contexto, só faltam os 4 perguntáveis |
| 2️⃣ **Confirmar** | Gera `PAGOU_PIX_INTEGRATION_PLAN.md` com lista exata de arquivos a criar/modificar, DDL, endpoints | Aprovação explícita do usuário |
| 3️⃣ **Implementar** | Aplica o adapter do framework — cliente, serviço, endpoint, webhook, persistência | Código pronto a rodar |
| 4️⃣ **Testar** | Gera e executa unit + integration + webhook + e2e | 100% verdes |
| 5️⃣ **Validar** | Percorre 5 checklists com evidência por item | Todos os críticos ✓ |
| 6️⃣ **Pontuar** | Calcula score 0–100 e gera relatório final | Classificação |

---

## 🚀 Instalação

### Pré-requisitos

- [Claude Code CLI](https://claude.com/claude-code) instalado

### Em dois comandos, dentro do Claude Code

```text
/plugin marketplace add antoniocostalopes/pagou-pix-integrator
/plugin install pagou-pix-integrator@pagou-pix-integrator
```

O primeiro comando registra este repositório como um marketplace local. O segundo instala o plugin a partir dele.

### Verificação

Depois de instalar, lista os teus plugins:

```text
/plugin
```

Deves ver `pagou-pix-integrator` listado como **enabled**. A skill fica disponível em qualquer projeto que abrires com o Claude Code.

### Atualizar

```text
/plugin marketplace update pagou-pix-integrator
/plugin install pagou-pix-integrator@pagou-pix-integrator
```

### Desinstalar

```text
/plugin uninstall pagou-pix-integrator@pagou-pix-integrator
/plugin marketplace remove pagou-pix-integrator
```

📖 Detalhes adicionais e troubleshooting: veja [**INSTALL.md**](./INSTALL.md).

---

## 💡 Uso

Dentro de qualquer projeto onde você queira adicionar PIX, no Claude Code:

```
/pagou-pix-integrator
```

Ou simplesmente peça em linguagem natural:

> _"Integra PIX via Pagou.ai neste projeto."_
>
> _"Adiciona um webhook da Pagou e implementa a cobrança PIX."_

A Skill cuida do resto. Você só precisa de:

1. 🔑 **`PAGOU_API_KEY`** — chave da sua conta Pagou
2. 🌐 **Ambiente** — sandbox ou produção
3. 🔗 **URL pública** do projeto (para registrar o webhook)
4. 🏷️ **Status internos** — como mapear `paid` → `pago` no seu domínio

---

## 🧰 Frameworks suportados

Cada adapter traz **código pronto a copiar**, específico para o stack, com cliente HTTP, serviço, endpoint, webhook, migrations e testes.

| | Framework | Adapter | Inclui |
|---|---|---|---|
| ⚫ | **Next.js** (App Router + Pages Router) | [`frameworks/nextjs.md`](./frameworks/nextjs.md) | Prisma · Vitest · TypeScript |
| 🔴 | **Laravel** (9, 10, 11) | [`frameworks/laravel.md`](./frameworks/laravel.md) | Eloquent · Jobs · Pest/PHPUnit |
| 🔵 | **WordPress** (6.0+) | [`frameworks/wordpress.md`](./frameworks/wordpress.md) | Plugin · REST API · wp-cron |
| 🟣 | **WooCommerce** (7.0+) | [`frameworks/woocommerce.md`](./frameworks/woocommerce.md) | Gateway WC · HPOS · meta de pedido |
| ⚪ | **Genérico** | [`frameworks/generic.md`](./frameworks/generic.md) | Express, FastAPI, Django, Rails, Go, .NET, … |

Não vê seu stack? O adapter genérico cobre o **contrato universal** (DDL, pseudocódigo, contratos de endpoint) que você adapta para qualquer linguagem.

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
| 🟢 **90–94** | Production Ready | Liberar com monitoramento extra |
| 🟡 **80–89** | Minor Improvements | Listar gaps e corrigir antes de prod |
| 🟠 **70–79** | Needs Review | Revisão humana obrigatória |
| 🔴 **0–69** | Not Ready | Não deploy. Re-trabalhar. |

> ⚠️ **Score abaixo de 90 não vai para produção sem revisão humana.**

Detalhes em [`docs/scoring-engine.md`](./docs/scoring-engine.md).

---

## 🛡️ Princípios não-negociáveis

Encodados em `CLAUDE.md` e validados em cada checklist:

| 🚫 Anti-padrão | ✅ Como a Skill faz |
|---|---|
| `PAGOU_API_KEY` no browser | Apenas backend, validado por grep negativo |
| Dedup por `data.id` (transação) | Dedup por `event.id` (top-level) — uma transação emite N eventos |
| `setStatus('paid')` após sucesso no browser | Estado final **só** via webhook ou GET de reconciliação |
| Valores em reais | Sempre em **centavos** (Pagou v2) — verificado por teste |
| Esquecer `external_ref` | Sempre presente — base de idempotência e reconciliação |
| Webhook handler com lógica pesada inline | ACK rápido `{"received": true}` + processamento assíncrono |
| Retry de `POST` em erro | Reconciliação via `GET`, não retentativa de criação |

---

## 🏗️ Arquitetura — o que é gerado no seu projeto

```
seu-projeto/
├── src/lib/pagou/                     (ou app/Services/Pagou/, plugins/pagou-pix/, etc.)
│   ├── client.ts                      ← wrapper HTTP autenticado
│   ├── pix.ts                         ← serviço PIX (criar + consultar)
│   └── status.ts                      ← mapeamento Pagou → status interno
│
├── app/api/pagou/pix/route.ts         ← endpoint público (criar cobrança)
├── app/api/webhooks/pagou/route.ts    ← endpoint webhook
│
├── prisma/migrations/                 ← 2 tabelas novas
│   └── add_pagou_pix/
│       ├── pagou_pix_transactions     ← UNIQUE external_ref + pagou_transaction_id
│       └── pagou_webhook_events       ← UNIQUE event_id (idempotência)
│
├── tests/pagou/                       ← 4 suítes
│   ├── status.test.ts                 (unit)
│   ├── client.test.ts                 (integration)
│   ├── webhook.test.ts                (dedup + processing)
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

## 📚 Documentação

### 🧠 Como a Skill pensa

- [`SKILL.md`](./SKILL.md) — contrato e fluxo da Skill (frontmatter YAML invocável)
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
- [`checklists/webhook.md`](./checklists/webhook.md)
- [`checklists/reconciliation.md`](./checklists/reconciliation.md)
- [`checklists/validation.md`](./checklists/validation.md)
- [`checklists/production.md`](./checklists/production.md)

### 🔬 Referência interna

- [`docs/architecture.md`](./docs/architecture.md) — visão da Skill e do código gerado
- [`docs/payment-flow.md`](./docs/payment-flow.md) — fluxo end-to-end de uma cobrança
- [`docs/webhook-flow.md`](./docs/webhook-flow.md) — handler, job, idempotência
- [`docs/scoring-engine.md`](./docs/scoring-engine.md) — algoritmo determinístico do score

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

## 🤝 Contribuindo

Contribuições são muito bem-vindas! Antes de abrir um PR:

1. 🍴 Faça um fork do repositório
2. 🌿 Crie uma branch: `git checkout -b feat/minha-melhoria`
3. ✏️ Faça as alterações respeitando os princípios em [`CLAUDE.md`](./CLAUDE.md)
4. 🧪 Se tocou em código de adapter, valide a sintaxe (PowerShell, Bash)
5. 📝 Atualize [`CHANGELOG.md`](./CHANGELOG.md)
6. 📨 Abra o PR descrevendo o **porquê** (não apenas o quê)

### Áreas onde ajuda é especialmente bem-vinda

- 🌐 Novos adapters de framework (Nuxt, SvelteKit, Symfony, Phoenix, Rails, Django, etc.)
- 🧪 Mais cenários nos testes e2e
- 🌍 Tradução para outras línguas (atualmente PT-BR)
- 🔌 Integração com endpoints adicionais da Pagou (subscriptions, transfers)
- 📊 Métricas e dashboards de operação

---

## 📅 Changelog

Veja [`CHANGELOG.md`](./CHANGELOG.md) para o histórico completo.

**Versão atual: `1.0.0`** — primeira release.

---

## 📜 Licença

[MIT](./LICENSE) © 2026 [AgencyCoders](https://github.com/antoniocostalopes)

---

<div align="center">

### Feito com 💸 para a comunidade brasileira de pagamentos

[**🐛 Reportar bug**](https://github.com/antoniocostalopes/pagou-pix-integrator/issues) • [**✨ Sugerir feature**](https://github.com/antoniocostalopes/pagou-pix-integrator/issues) • [**⭐ Star no GitHub**](https://github.com/antoniocostalopes/pagou-pix-integrator)

</div>
