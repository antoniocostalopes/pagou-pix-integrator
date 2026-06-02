# Changelog

Todas as mudanças notáveis nesta Skill são documentadas aqui.

O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/), e a versão segue [SemVer](https://semver.org/lang/pt-BR/).

## [1.1.1] — 2026-06-02

### Alterado

- **README.md** — Quick start agora destaca `git clone` como caminho recomendado (1 comando). O caminho `/plugin marketplace add` + `/plugin install` continua disponível como alternativa para quem prefere o sistema de plugins do Claude Code.
- **README.md** — Secção de Instalação reorganizada: `git clone` como caminho principal (com subsecções de update, uninstall e variante symlink), `/plugin marketplace` como alternativa com lifecycle integrado.
- **INSTALL.md** — Reescrito para refletir ambos os caminhos lado a lado, com tabela comparativa e troubleshooting para os dois.

### Justificativa

Após confirmar que ambos os caminhos funcionam de forma nativa no Claude Code (git clone para `~/.claude/skills/` é o mesmo mecanismo das skills built-in como `find-skills` e `oss-ai-compliance`), promovemos o caminho de 1 comando para uso pessoal. O caminho de 2 comandos via marketplace continua a ser o ideal para distribuição profissional com lifecycle (`enable`/`disable`/`update`).

## [1.1.0] — 2026-06-02

### Adicionado

- `.claude-plugin/plugin.json` — manifesto do plugin (necessário para instalação via `/plugin install`)
- `.claude-plugin/marketplace.json` — manifesto de marketplace para o fluxo `/plugin marketplace add antoniocostalopes/pagou-pix-integrator`
- INSTALL.md reescrito em torno do fluxo nativo do Claude Code (sem scripts)
- README.md com a secção de instalação simplificada para os dois comandos canónicos

### Removido

- `install.ps1` — scripts customizados substituídos pelo sistema de plugins nativo
- `install.sh` — idem

### Justificativa

A instalação agora segue o padrão das skills oficiais (Figma, etc.): o utilizador adiciona o repo como marketplace e instala o plugin a partir dele, tudo a partir de comandos do Claude Code. Não há ficheiros para copiar manualmente nem scripts a executar.

## [1.0.0] — 2026-06-02

### Adicionado

- Estrutura completa da Skill conforme PRD
- `SKILL.md` com frontmatter YAML invocável (`/pagou-pix-integrator`)
- `CLAUDE.md` com regras de execução das 6 fases
- `KNOWLEDGE.md` com a verdade da API Pagou.ai v2 (endpoints, payloads, status, webhooks)
- 5 framework adapters com código pronto a copiar:
  - `frameworks/nextjs.md` — App Router + Pages Router, Prisma, Vitest
  - `frameworks/laravel.md` — Eloquent, Queues, Pest/PHPUnit
  - `frameworks/wordpress.md` — Plugin com REST API + wp-cron
  - `frameworks/woocommerce.md` — Gateway WC com HPOS
  - `frameworks/generic.md` — Pseudocódigo + DDL universal por stack
- 9 prompts executáveis (discovery × 2, missing-data, integration-plan, pix-integration, webhook-integration, reconciliation, validation, scoring)
- 5 templates de relatórios obrigatórios (PLAN, REPORT, SCORE, README_PAGOU_PIX, TEST_REPORT)
- 5 checklists de validação (security, webhook, reconciliation, validation, production)
- 4 documentos internos de referência (architecture, payment-flow, webhook-flow, scoring-engine)
- Scripts de instalação (`install.ps1` para Windows, `install.sh` para Unix)
- `INSTALL.md` com instruções de instalação local e global
- Licença MIT

### Princípios encodados

- Fluxo imutável: Descobrir → Confirmar → Implementar → Testar → Validar → Pontuar
- Apenas 4 perguntas permitidas ao usuário (API key, env, URL pública, status internos)
- Dedup obrigatória por `event.id` (top-level) — nunca por `data.id`
- Valores em centavos (Pagou v2)
- `external_ref` obrigatório em toda criação
- Webhook ACK rápido `{ received: true }` antes do processamento
- API key apenas backend
- Score 0–100 com pesos exatos do PRD (15/15/20/20/15/15)
