# Changelog

Todas as mudanças notáveis nesta Skill são documentadas aqui.

O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/), e a versão segue [SemVer](https://semver.org/lang/pt-BR/).

## [3.0.1] — 2026-06-03

Fecha 3 gaps críticos identificados na comparação com a doc oficial da Pagou (`developer.pagou.ai`). PATCH — sem alteração de contrato nem novas dependências.

### Adicionado

- **Captura e log de `requestId`** em todos os 5 adapters de framework (Next.js, Laravel, WordPress, WooCommerce, Generic). O cliente HTTP gerado passa a ler `x-request-id` (ou `x-pagou-request-id`) da resposta da Pagou e a logar em toda chamada (`event: "pagou.api.call"`). O `requestId` é propagado em `PagouError`/`PagouException` para facilitar troubleshooting com o suporte oficial da Pagou.
- **Nova secção "Tracing — `requestId`"** em `KNOWLEDGE.md` — regras de logging, headers a procurar, propagação em exceções.
- **Novo item crítico** em `checklists/validation.md` validando que o cliente HTTP loga `requestId` quando devolvido.
- **Aviso explícito de divergência com recomendação oficial Pagou** sempre que o utilizador escolhe modo `polling`. Aparece em 4 sítios:
  - `prompts/missing-data.md` — bloco de aviso após a escolha
  - `templates/PAGOU_PIX_INTEGRATION_PLAN.md` — aviso no plano gerado
  - `templates/PAGOU_PIX_INTEGRATION_REPORT.md` — aviso no relatório final
  - `templates/README_PAGOU_PIX.md` — aviso no guia operacional
  - Texto cita literalmente a doc oficial: *"Use GET polling only for reconciliation, support, or recovery, never as the primary flow."* e lista trade-offs concretos (latência, custo de API, eventos tardios).
- **Nota explícita sobre SDK `@pagouai/api-sdk`** em `KNOWLEDGE.md` — avisa que documentação oficial pode mostrar `environment: "sandbox"`, mas a Skill v3+ exige `"production"`. Inclui ponteiro para `tools/pagou-mock/` como alternativa para dev/CI.

### Alterado

- `frameworks/nextjs.md` — `PagouError` ganha campo `requestId?: string`; `pagouFetch` loga `pagou.api.call` com requestId.
- `frameworks/laravel.md` — `PagouException` ganha campo `?string $requestId`; `handle()` loga `pagou.api.call`.
- `frameworks/wordpress.md` — `Pagou_Pix_Client::request()` loga `pagou.api.call` e devolve `request_id` em erro.
- `frameworks/woocommerce.md` — `Pagou_Pix_WC_Client::request()` idem.
- `frameworks/generic.md` — pseudocódigo do cliente HTTP inclui captura de `requestId` e regra de logging.

### Não alterado

- Contrato de 4 perguntas, modos de confirmação webhook/polling, URL hardcoded em produção, anti-padrões, scoring, fluxo das 6 fases. Esta release é puramente aditiva.

## [3.0.0] — 2026-06-03

Remove totalmente o suporte a sandbox. A Skill agora chama **apenas produção** (`https://api.pagou.ai`). Para dev/CI sem cobranças reais, `tools/pagou-mock/` (incluído no repo) é o caminho suportado.

### ⚠️ BREAKING CHANGES

- **Lista canónica de perguntas passa de 5 para 4.** A pergunta "Sandbox ou Produção" desaparece. As 4 perguntas actuais: API key, modo de confirmação, URL pública (se webhook), status internos.
- **Variável de ambiente `PAGOU_ENV` removida** de todos os adapters, templates, prompts e docs. Cliente HTTP deixa de a ler.
- **Variável de ambiente `PAGOU_BASE_URL` removida.** Não há mais override do base URL — é constante hardcoded.
- **Em todos os 5 adapters de framework, o mapa `{sandbox, production} → URL` é substituído por uma constante**:
  - `frameworks/nextjs.md` — `const PAGOU_BASE_URL = "https://api.pagou.ai"`
  - `frameworks/laravel.md` — `private const BASE_URL = 'https://api.pagou.ai'`
  - `frameworks/wordpress.md` — `const BASE = 'https://api.pagou.ai'`
  - `frameworks/woocommerce.md` — `const BASE = 'https://api.pagou.ai'`
  - `frameworks/generic.md` — pseudocódigo refere "constante hardcoded"
- **Painel admin em WordPress/WooCommerce remove o selector "Sandbox/Produção"** — fica só o campo `API Key (PRODUÇÃO)` com aviso sobre `tools/pagou-mock/` para dev local.
- **`KNOWLEDGE.md` tabela de documentação oficial deixa de listar URL de sandbox** (a Pagou pode continuar a tê-lo, mas a Skill não suporta). Adiciona nota explícita: *"a Skill v3+ só fala com produção; usar `tools/pagou-mock/` para dev"*.
- **Detecção de produção para fail-closed em HMAC** passa a usar runtimes do framework (`NODE_ENV`, `APP_ENV`, etc.) em vez de `PAGOU_ENV`.

### Adicionado

- **Promoção do `tools/pagou-mock/`** como o único caminho oficial para dev/CI sem tocar em produção. Documentado em SKILL.md, CLAUDE.md, KNOWLEDGE.md, README, todos os templates e checklists.
- **Aviso explícito ao utilizador** durante a 1ª pergunta de que a chave colada é de produção.

### Alterado

- `SKILL.md` — secção "Perguntas permitidas" volta a 4 linhas; nova subsecção "Apenas produção (desde v3.0.0)" explicando a remoção.
- `CLAUDE.md` — Fase 1 critério de saída lista 4 perguntáveis; Fase 3 passo 1 menciona que `PAGOU_ENV` não é configurado; passo 3 explicita base URL constante.
- `prompts/missing-data.md` — reescrito com nova ordem (key → modo → URL → status), template de mensagem ao utilizador actualizado, secção "O que nunca perguntar" ganha entrada "Sandbox ou produção?".
- `prompts/integration-plan.md`, `prompts/pix-integration.md`, `prompts/scoring.md` — remoção de menções a `PAGOU_ENV` e sandbox.
- `templates/PAGOU_PIX_INTEGRATION_PLAN.md` — campo "Ambiente Pagou escolhido" substituído por "API Pagou alvo" (constante).
- `templates/PAGOU_PIX_INTEGRATION_REPORT.md` — campo "Ambiente alvo" idem; testes apontam para mock.
- `templates/README_PAGOU_PIX.md` — secção "Variáveis de ambiente" simplificada; secção "Base URLs" substituída por "Como testar localmente sem cobranças reais".
- `templates/TEST_REPORT.md` — secção "Criar cobrança em sandbox" → "Criar cobrança contra `tools/pagou-mock/`".
- `checklists/production.md`, `checklists/validation.md`, `checklists/reconciliation.md`, `checklists/webhook.md` — remoção de menções a sandbox; promoção do mock como caminho de teste.
- README.md — "5 informações" volta a "4 informações"; tabela de features ganha entrada "Apenas produção".

### Removido

- Variáveis de ambiente `PAGOU_ENV` e `PAGOU_BASE_URL` de todo o código gerado e da documentação.
- URL `https://api-sandbox.pagou.ai` de todos os ficheiros (excepto referências históricas no CHANGELOG).
- Pergunta "Sandbox ou Produção?" do contrato da Skill.
- Selector "Sandbox/Produção" dos painéis admin de WordPress e WooCommerce.

### Não alterado

- `tools/pagou-mock/` (que já existia em 1.2.0) — continua a ser o servidor de simulação local. Promovido agora a caminho oficial de dev/CI em vez de ser opcional.
- HMAC, dedup por `event.id` top-level, idempotência tripla, valores em centavos, `external_ref`, ACK rápido — todos os invariantes técnicos do contrato com a Pagou v2 mantêm-se.
- Modo de confirmação webhook vs polling (introduzido em 2.0.0). Continua a ser a 2ª pergunta agora.

### Migração de 2.0.0 para 3.0.0

Para utilizadores actuais com integração feita pela v2:

1. Remover `PAGOU_ENV` e `PAGOU_BASE_URL` do `.env` e do `.env.example`.
2. Confirmar que `PAGOU_API_KEY` é a chave de **produção** da Pagou (não sandbox).
3. No cliente HTTP do projecto, substituir o mapa `{sandbox, production} → URL` por `const PAGOU_BASE_URL = "https://api.pagou.ai"`.
4. Substituir checks de `process.env.PAGOU_ENV === "production"` por checks ao runtime do framework (`NODE_ENV`, `APP_ENV`, etc.).
5. Para dev local, apontar o cliente HTTP para `tools/pagou-mock/` (porta default 8787) em vez de `api-sandbox.pagou.ai`.

A Skill executada num projecto já integrado deve detectar isto no Descobrir e propor a migração via aprovação humana.

## [2.0.0] — 2026-06-03

Modo de confirmação de pagamento agora é **configurável** — webhook (default, recomendado) ou polling-only (opt-out, mais simples).

### ⚠️ BREAKING CHANGES

- **Contrato de perguntas passa de 4 para 5.** A Skill agora pergunta também `PAGOU_CONFIRMATION_MODE` (`webhook` | `polling`). Consumidores que dependiam da lista canónica de 4 perguntas em `prompts/missing-data.md` têm de atualizar expectativa.
- **Invariante "webhook sempre obrigatório" relaxado** para "webhook é o default recomendado". Em modo `polling`, o utilizador pode legitimamente nunca registar o webhook no painel da Pagou. O endpoint continua a ser gerado em ambos os modos para permitir upgrade futuro sem regenerar código.
- **`KNOWLEDGE.md` regra de ouro #4 reescrita:** de *"Webhooks são a fonte da verdade — polling com GET só para reconciliação/recuperação/suporte"* para *"Webhooks são o padrão recomendado; GET é o caminho alternativo quando o utilizador escolhe `PAGOU_CONFIRMATION_MODE=polling`"*.
- **Checklists** `webhook.md` e `reconciliation.md` agora têm secções condicionais por modo. Itens operacionais do webhook (registo no painel, secret HMAC) ficam N/A em modo `polling`. Itens de reconciliação tornam-se mais rigorosos em modo `polling`.

### Adicionado

- **5ª pergunta — modo de confirmação** em `prompts/missing-data.md`. Default = `webhook`. Aceita também `polling` / `p` / `2` / `só polling`.
- **Background poller curto** (`pagou:poll` / cron equivalente) gerado em todos os 5 adapters (`nextjs`, `laravel`, `wordpress`, `woocommerce`, `generic`) quando modo = `polling`. Corre cada 1 minuto, consulta `GET /v2/transactions/{id}` para transações pending na última hora, propaga status terminais para o pedido.
- **Job de reconciliação tardia** (`pagou:reconcile-late`) — gerado em ambos os modos, frequência depende do modo (horária em webhook, cada 15 min em polling). Apanha eventos pós-pagamento (`refunded`, `partially_refunded`, `chargedback`) que o caminho principal pode ter perdido.
- **Variável de ambiente `PAGOU_CONFIRMATION_MODE`** (`webhook` | `polling`) — sempre presente no `.env.example` gerado.
- Templates `PAGOU_PIX_INTEGRATION_PLAN.md`, `PAGOU_PIX_INTEGRATION_REPORT.md` e `README_PAGOU_PIX.md` ganham secções condicionais por modo, incluindo limitações conhecidas em modo polling (latência, custo de API, eventos tardios).

### Alterado

- **`SKILL.md` secção "Perguntas permitidas"** passa de tabela de 4 para tabela de 5 + nova subsecção "Modo de confirmação — webhook vs polling".
- **`CLAUDE.md` Fase 2** lista 5 perguntáveis; Fase 3 menciona ramificação por modo na ordem de implementação (passos 6, 7 e 8 explicitam dependência do modo).
- **`prompts/integration-plan.md`** plano gerado mostra modo escolhido + consequências (webhook → registo no painel; polling → poller + reconciliação 15 min).
- **`prompts/webhook-integration.md`** introdução explicita que o endpoint é gerado em ambos os modos.
- **`prompts/reconciliation.md`** explicitamente tratado como caminho principal em modo polling, fallback em modo webhook.
- **Adapters de framework** (`nextjs.md`, `laravel.md`, `wordpress.md`, `woocommerce.md`, `generic.md`) ganham secção final "Modo polling-only" com código/pseudocódigo específico do scheduler de cada stack (Vercel Cron, Laravel Schedule, wp-cron, Action Scheduler do WooCommerce, padrões genéricos).
- **README.md** secção "Uso" passa a listar 5 dados; tabela de features ganha entrada "Modo configurável"; secção "Princípios não-negociáveis" ajusta a linha "estado final só por webhook" para incluir polling backend e reconciliação.

### Removido

- Linguagem "obrigatório no PRD" em torno de webhook no `prompts/missing-data.md` — passa a "padrão recomendado".

### Não alterado

- **Endpoint de webhook é sempre gerado** — em ambos os modos. Permite upgrade futuro sem regenerar.
- HMAC-SHA256, dedup por `event.id` top-level, ACK rápido, idempotência tripla, valores em centavos, `external_ref` obrigatório, fail-closed em prod — todos os invariantes técnicos da API Pagou v2 mantêm-se. O que muda é o caminho operacional, não o contrato da API.
- Status mapping default em PT-BR, anti-padrões automáticos, fluxo das 6 fases, scoring 0–100.

### Migração de 1.2.x para 2.0.0

Quem actualiza e corre a Skill num projeto novo: nada muda no comportamento default — é-lhe feita a 5ª pergunta e se carregar Enter / responder "webhook", o resultado é equivalente ao 1.2.2.

Quem actualiza e corre a Skill num projeto já integrado: a Skill detecta no Descobrir que existe `pagou_pix_transactions` + `pagou_webhook_events` e pode propor mudança de modo via aprovação humana — sem regenerar o que já está.

## [1.2.2] — 2026-06-03

Release de descoberta. Sem alteração funcional — só clarifica como o utilizador final invoca a Skill.

### Alterado

- **`SKILL.md`** — campo `description` no frontmatter passa a mencionar explicitamente o slash command `/pagou-pix-integrator` como invocação canónica, mantendo as frases em linguagem natural como caminho alternativo. Aumenta a discoverability quando a Skill aparece em catálogos do Claude Code.
- **`README.md` — secção "Uso"** reestruturada com dois subtítulos:
  - **Caminho canónico — slash command** — promove `/pagou-pix-integrator` como entry point oficial, com dica de autocomplete (`/p` + Tab).
  - **Alternativa — linguagem natural** — preserva as frases naturais, agora claramente posicionadas como fallback amigável.
- **`README.md` — secção "Changelog"** corrige a versão mencionada (estava `1.2.0` mesmo após o release `1.2.1`).

### Não alterado

- Fluxo de 6 fases, anti-padrões, contrato com o utilizador, frameworks suportados, score. Nada disto muda — esta release é puramente documental e de metadados.

### Removido

- Ficheiro `LICENSE` (que continha o texto MIT).
- Campo `"license": "MIT"` em `.claude-plugin/plugin.json`.
- Campo `"license": "MIT"` em `.claude-plugin/marketplace.json`.
- Badge `License: MIT` no header do README.
- Entrada `LICENSE` na lista de ficheiros obrigatórios em `.github/workflows/ci.yml`.

### Nota importante

A licença MIT que constou nas versões `1.0.0` até `1.2.0` foi assumida pela configuração inicial e nunca foi confirmada pelo dono do projeto. **A partir de `1.2.1` o projeto não tem licença open source explícita** — todos os direitos reservados pelo autor por defeito.

Quem fez fork ou clone das versões anteriores assumindo termos MIT deve confirmar diretamente com o autor antes de redistribuir, modificar ou usar comercialmente. Quem clonar a partir de `1.2.1` precisa de permissão explícita do autor para qualquer uso para além de utilização pessoal não-comercial.

## [1.2.0] — 2026-06-02

Release de hardening para produção. Cinco frentes ao mesmo tempo: segurança, domain coverage, observabilidade, repo hygiene e DX.

### Adicionado — Segurança

- **Verificação HMAC-SHA256 do webhook.** Header `X-Pagou-Signature` validado contra `HMAC-SHA256(rawBody, PAGOU_WEBHOOK_SECRET)` com comparação em tempo constante. Em produção sem secret → boot falha (fail closed). Em dev sem secret → log warning + permitido (fail open). Documentado em `KNOWLEDGE.md` e implementado em `frameworks/nextjs.md`, `frameworks/laravel.md`, `frameworks/generic.md`. Variável `PAGOU_WEBHOOK_SECRET` adicionada aos `.env.example` dos adapters.
- **Política de segurança** (`SECURITY.md`) com janela de resposta, escopo, e instruções para reportar vulnerabilidades via GitHub Security Advisories.

### Adicionado — Funcionalidade

- **Cancelamento de PIX pendente** (`POST /v2/transactions/{id}/cancel`). Endpoint admin em Next.js e Laravel. Pseudocódigo no adapter genérico.
- **Estorno (refund) total e parcial** (`POST /v2/transactions/{id}/refund`). Endpoint admin com validação, auditoria via log, e nota explícita de que o status final espera pelo webhook `transaction.refunded` / `.partially_refunded`.
- **Frontend snippets** em cada adapter:
  - Next.js: hook `usePagouPix` + componente `PixCheckout` (React)
  - Laravel: Blade component com Alpine.js
  - Genérico: princípios universais e tabela de anti-padrões
  - Todos incluem o prefixo `data:image/png;base64,` obrigatório no QR

### Adicionado — Observabilidade

- `docs/observability/metrics.md` — definição de 15 métricas Prometheus/OTel (cobrança, webhook, reconciliação, refund/cancel, saúde API) com snippets para Node.js, Laravel, Python, Go.
- `docs/observability/prometheus-alerts.yml` — 8 regras de alerta prontas (webhook errors, invalid signatures, silence detection, latência, drift de reconciliação).
- `docs/observability/grafana-dashboard.json` — dashboard com 9 painéis em 3 linhas (Cobrança · Webhooks · Reconciliação) pronto para importar.
- `checklists/production.md` atualizado para referenciar estes assets como critérios.

### Adicionado — Repo hygiene

- `.github/workflows/ci.yml` — CI completo: validação de `plugin.json` e `marketplace.json`, version consistency entre 4 ficheiros, frontmatter YAML do `SKILL.md`, presença de ficheiros obrigatórios, markdownlint, link checker, JSON syntax, shell syntax.
- `.markdownlint.json` — configuração mínima permitindo HTML inline e linhas longas.
- `.github/ISSUE_TEMPLATE/bug_report.md`, `feature_request.md`, `adapter_request.md`.
- `.github/PULL_REQUEST_TEMPLATE.md` com checklist dos princípios não-negociáveis.
- `CONTRIBUTING.md` com setup, tipos de contribuição valorizados, SemVer policy.
- `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1).

### Adicionado — DX

- `tools/pagou-mock/` — mock server stand-alone em Node 20 (zero deps externas) que implementa as 4 rotas v2 usadas pela Skill (`create`, `get`, `cancel`, `refund`) e dispara webhooks de volta com HMAC válido. Cenários por prefixo de `external_ref`: `expire-`, `refuse-`, `chargeback-`, `slow-`, `silent-`.
- `tools/webhook-tester/` — script Bash que envia webhooks simulados com assinatura HMAC válida para o teu endpoint local. Útil para testar dedup e cenários compostos.

### Alterado

- `KNOWLEDGE.md` agora documenta cancel + refund endpoints, secção HMAC do webhook, e clarifica que estado final espera pelo webhook.
- `prompts/webhook-integration.md` atualizado para incluir verificação HMAC como passo 0 do handler.
- `checklists/webhook.md` — verificação HMAC promovida a critério crítico.
- `checklists/security.md` — removido "HMAC do webhook" dos recomendados (agora é obrigatório).

### Bump version

`1.1.1` → `1.2.0` em `SKILL.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, README badge.

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
