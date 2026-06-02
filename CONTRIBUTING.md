# Como contribuir

Obrigado por considerar contribuir! Esta Skill cresce com PRs da comunidade — adapters novos, melhorias de segurança, traduções, docs.

## Antes de começar

1. **Lê o [`CLAUDE.md`](./CLAUDE.md)** — encoda os princípios não-negociáveis (dedup por `event.id`, centavos, etc.). Toda contribuição deve respeitá-los.
2. **Lê o [`KNOWLEDGE.md`](./KNOWLEDGE.md)** — a verdade sobre a API Pagou v2. Não inventes endpoints ou campos.
3. **Procura na lista de issues** — talvez já estejam a trabalhar no que tu queres.

## Setup local

```bash
git clone https://github.com/antoniocostalopes/pagou-pix-integrator.git
cd pagou-pix-integrator

# Opcional: usar como skill enquanto desenvolves (Unix)
ln -s "$(pwd)" ~/.claude/skills/pagou-pix-integrator

# Windows (PowerShell, Developer Mode ou Admin)
New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\.claude\skills\pagou-pix-integrator" -Target "$(Get-Location)"
```

## Tipos de contribuição valorizados

### 🌐 Novo framework adapter

Para adicionar suporte a um novo stack (Nuxt, SvelteKit, Symfony, Rails, ...), copia `frameworks/generic.md` como base e cria `frameworks/<framework>.md`. Cobre **no mínimo**:

- Detecção (sinais em manifestos)
- Variáveis de ambiente
- Migração de DB
- Cliente Pagou (auth, base URL por env)
- Status mapping
- Endpoint de criar cobrança
- Endpoint webhook **com verificação HMAC**
- Endpoints admin de **cancel** e **refund**
- Reconciliação
- Testes (unit + integration + webhook + e2e)
- Frontend snippet (renderizar QR com prefixo `data:image/png;base64,`)

### 🐛 Bug fix

- Reproduz primeiro com teste antes de corrigir
- Se a correção é numa convenção partilhada (e.g., `KNOWLEDGE.md`), atualiza **todos** os adapters afetados na mesma PR

### 📊 Melhoria de score

- Adicionar critérios novos requer atualizar `docs/scoring-engine.md`
- Não introduzir critérios subjetivos — devem ser verificáveis com grep/teste/file existence

### 🛡️ Segurança

- Para vulnerabilidades, **não abrir PR pública** — segue `SECURITY.md`
- Para hardening proativo (adicionar rate limit, CSRF, etc.), PR normal

### 🌍 Tradução

Hoje só PT-BR. Para adicionar EN/ES:

- Criar `i18n/<lang>/` com os documentos traduzidos
- Atualizar SKILL.md frontmatter `description` com formato multi-language ou criar `SKILL.<lang>.md`

## Estilo de código

### Markdown

- Frase em **português brasileiro**, código em inglês (variáveis, funções, ficheiros)
- Tabelas em vez de listas longas quando comparativas
- Emojis para hierarquia visual (não excessivos)
- Code blocks com linguagem identificada (` ```ts `, ` ```php `)

### Code snippets dentro dos adapters

- **Funcional** — copy-paste deve produzir código que compila/roda
- **Idiomático** ao framework — não impor estilo de outro stack
- **Comentários mínimos** — só onde a intenção não é óbvia
- **Sem segredos hardcoded** — usar env vars com placeholder

## Fluxo de PR

1. Fork → branch (`feat/...`, `fix/...`, `docs/...`)
2. Commit messages em **imperativo inglês** (`feat(adapters): add nuxt adapter`)
3. Bump version em `SKILL.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` e badge do README (SemVer)
4. Atualizar `CHANGELOG.md` com entrada na secção `## [unreleased]` ou nova versão
5. Abrir PR usando o template
6. Esperar pela CI verde (validação JSON, lint, link check, version consistency)
7. Pelo menos 1 review antes de merge

## SemVer

| Tipo de mudança | Bump |
|---|---|
| Bug fix | PATCH |
| Adapter novo, métrica nova, endpoint admin novo | MINOR |
| Mudança que quebra adapter existente, renomeia env var, muda contrato | MAJOR |
| Documentação sem mudança de comportamento | PATCH ou sem bump |

## Code of conduct

Este projeto segue o [Contributor Covenant](./CODE_OF_CONDUCT.md). Em resumo: sê respeitoso, recebe feedback com humildade, dá feedback construtivo.

## Dúvidas

- Abre issue com label `question`
- Ou comenta numa issue existente
