# Instalação — Pagou PIX Integrator

Este plugin é instalado pelo Claude Code através do sistema nativo de **marketplaces de plugins**. Sem scripts, sem cópia manual de pastas.

## Pré-requisitos

- [Claude Code CLI](https://claude.com/claude-code) instalado e funcionando
- Acesso ao GitHub (a CLI usa o teu auth do `gh` ou um token Git padrão para clonar marketplaces)

## Instalação

Dentro do Claude Code, executa:

```text
/plugin marketplace add antoniocostalopes/pagou-pix-integrator
/plugin install pagou-pix-integrator@pagou-pix-integrator
```

**O que cada comando faz:**

| Comando | Efeito |
|---|---|
| `/plugin marketplace add antoniocostalopes/pagou-pix-integrator` | Clona o repo como uma fonte de plugins (lê `.claude-plugin/marketplace.json`) |
| `/plugin install pagou-pix-integrator@pagou-pix-integrator` | Instala o plugin `pagou-pix-integrator` que veio desse marketplace |

A sintaxe é `nome-do-plugin@nome-do-marketplace`. Aqui ambos são `pagou-pix-integrator` porque este repo é um marketplace de um único plugin.

## Verificação

```text
/plugin
```

Procura `pagou-pix-integrator` na lista; o estado deve ser **enabled**. Em seguida, em qualquer projeto, podes invocar a skill por nome:

```text
/pagou-pix-integrator
```

Ou simplesmente pedir em linguagem natural:

> _"Integra PIX via Pagou.ai neste projeto."_

O Claude reconhece o intent e carrega a skill automaticamente.

## Atualizar

Quando uma nova versão for publicada no repo:

```text
/plugin marketplace update pagou-pix-integrator
/plugin install pagou-pix-integrator@pagou-pix-integrator
```

O `marketplace update` faz `git pull` no marketplace; o `install` reinstala o plugin com a versão nova.

## Desinstalar

```text
/plugin uninstall pagou-pix-integrator@pagou-pix-integrator
/plugin marketplace remove pagou-pix-integrator
```

O primeiro remove o plugin instalado. O segundo remove o marketplace local.

## Instalação por projeto vs. global

O sistema de plugins do Claude Code suporta scopes diferentes. Por padrão a instalação é **user-level** (global) — o plugin fica disponível em qualquer projeto.

Para instalar apenas num projeto específico, ver a documentação oficial do `/plugin` sobre scopes (`--scope project`).

## Repositório privado

Se este repo estiver privado, o teu CLI precisa estar autenticado no GitHub para conseguir cloná-lo:

```bash
gh auth login
```

Depois disso, o `/plugin marketplace add` consegue aceder.

## Troubleshooting

### `marketplace add` falha com erro de autenticação

Confirma que estás autenticado:

```bash
gh auth status
```

Se não estiveres, autentica-te:

```bash
gh auth login
```

### A skill não aparece como invocável após instalação

1. Confirma na listagem: `/plugin` → o estado de `pagou-pix-integrator` é **enabled**?
2. Se aparecer **disabled**, ativa: `/plugin enable pagou-pix-integrator@pagou-pix-integrator`
3. Reinicia o Claude Code (fecha e abre o terminal)

### "Plugin não encontrado" no `/plugin install`

Confirma o nome exacto do plugin no marketplace:

```text
/plugin marketplace list
```

A sintaxe é sensível: `nome-do-plugin@nome-do-marketplace`. Para este projeto: `pagou-pix-integrator@pagou-pix-integrator`.

### Versão antiga mesmo após atualizar

Força a reinstalação:

```text
/plugin uninstall pagou-pix-integrator@pagou-pix-integrator
/plugin marketplace update pagou-pix-integrator
/plugin install pagou-pix-integrator@pagou-pix-integrator
```

## Como o plugin se estrutura no disco

Após instalado, o plugin vive em:

| Sistema | Caminho |
|---|---|
| macOS / Linux | `~/.claude/plugins/pagou-pix-integrator/` |
| Windows | `%USERPROFILE%\.claude\plugins\pagou-pix-integrator\` |

Nunca precisas de tocar nesses ficheiros manualmente — a CLI gere tudo.

## Onde o plugin atua

O plugin **não** modifica nada na tua máquina ou na pasta `~/.claude/`. Ele apenas é carregado pelo Claude Code quando invocas `/pagou-pix-integrator` dentro de um projeto.

Todo o trabalho efetivo da Skill acontece **no projeto-alvo** onde a invocas:

- Lê os ficheiros do projeto (descoberta)
- Gera código no projeto (cliente Pagou, endpoint, webhook, testes)
- Cria relatórios no projeto (PLAN, REPORT, SCORE, TEST_REPORT)

A Skill em si é apenas um conjunto de instruções, templates e código adapter.
