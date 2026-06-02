# Instalação — Pagou PIX Integrator

Este projeto suporta **dois caminhos de instalação**, ambos nativos do Claude Code:

| Caminho | Comandos | Quando usar |
|---|---|---|
| 🟢 **git clone** | 1 | Uso pessoal, setup rápido, desenvolvimento |
| 🟣 **/plugin marketplace** | 2 | Distribuição profissional, lifecycle completo (`enable`/`disable`/`update`) |

## Pré-requisitos

- [Claude Code CLI](https://claude.com/claude-code) instalado e funcionando
- Git no sistema
- Acesso ao GitHub (a CLI usa o teu auth para clonar repos privados)

---

## 🟢 Caminho recomendado — git clone

### Windows (PowerShell)

```powershell
git clone https://github.com/antoniocostalopes/pagou-pix-integrator.git "$env:USERPROFILE\.claude\skills\pagou-pix-integrator"
```

### macOS / Linux / WSL

```bash
git clone https://github.com/antoniocostalopes/pagou-pix-integrator.git ~/.claude/skills/pagou-pix-integrator
```

**Como funciona:** o Claude Code, ao arrancar, varre `~/.claude/skills/*/SKILL.md` e carrega qualquer skill que encontrar. O nosso repo tem `SKILL.md` no root com frontmatter YAML válido — o resto vem de borla.

### Verificação

Reinicia o Claude Code (fecha e abre a sessão), depois:

```text
/help
```

Deves ver `pagou-pix-integrator` na lista de skills disponíveis. Em qualquer projeto:

```text
/pagou-pix-integrator
```

### Atualizar

```bash
# Unix
git -C ~/.claude/skills/pagou-pix-integrator pull

# Windows
git -C "$env:USERPROFILE\.claude\skills\pagou-pix-integrator" pull
```

### Desinstalar

```bash
# Unix
rm -rf ~/.claude/skills/pagou-pix-integrator

# Windows
Remove-Item -Recurse -Force "$env:USERPROFILE\.claude\skills\pagou-pix-integrator"
```

### Variante: symlink (para desenvolvimento)

Se estás a editar a skill e queres que mudanças locais fiquem activas imediatamente:

```powershell
# Windows (requer Developer Mode ou Admin)
New-Item -ItemType SymbolicLink `
  -Path "$env:USERPROFILE\.claude\skills\pagou-pix-integrator" `
  -Target "C:\caminho\para\teu\folder\pagou-pix-integrator"
```

```bash
# Unix
ln -s /caminho/para/teu/folder/pagou-pix-integrator ~/.claude/skills/pagou-pix-integrator
```

---

## 🟣 Caminho alternativo — /plugin marketplace

Dentro do Claude Code:

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

### Verificação

```text
/plugin
```

Procura `pagou-pix-integrator`; o estado deve ser **enabled**.

### Atualizar

```text
/plugin marketplace update pagou-pix-integrator
/plugin install pagou-pix-integrator@pagou-pix-integrator
```

### Desativar (mantém instalada)

```text
/plugin disable pagou-pix-integrator@pagou-pix-integrator
```

### Desinstalar

```text
/plugin uninstall pagou-pix-integrator@pagou-pix-integrator
/plugin marketplace remove pagou-pix-integrator
```

---

## Repositório privado

Se este repo estiver privado, o teu CLI precisa estar autenticado no GitHub para conseguir cloná-lo. Em qualquer dos dois caminhos:

```bash
gh auth login
```

Depois disso, ambos `git clone` e `/plugin marketplace add` conseguem aceder.

---

## Troubleshooting

### A skill não aparece após instalação

1. Confirma que o folder existe: `dir "$env:USERPROFILE\.claude\skills\pagou-pix-integrator"` (Windows) ou `ls ~/.claude/skills/pagou-pix-integrator` (Unix)
2. Confirma que `SKILL.md` está no root e começa com `---`
3. Reinicia o Claude Code (fecha e abre o terminal)
4. Em sessão nova: `/help` — a skill deve aparecer

### `git clone` falha com "authentication required"

Se o repo for privado, autentica o `gh`:

```bash
gh auth status
gh auth login   # se não estiveres autenticado
```

### `/plugin marketplace add` falha

Confirma que estás autenticado e que o repo existe:

```bash
gh repo view antoniocostalopes/pagou-pix-integrator
```

Se for `404`, ou o repo está privado e tu não tens acesso, ou o nome está errado.

### "Plugin não encontrado" no `/plugin install`

Confirma o nome exato do plugin no marketplace:

```text
/plugin marketplace list
```

A sintaxe é sensível: `nome-do-plugin@nome-do-marketplace`. Para este projeto: `pagou-pix-integrator@pagou-pix-integrator`.

### Versão antiga mesmo após `git pull`

Reinicia o Claude Code — a skill é lida no arranque, mudanças só são apanhadas em sessão nova.

---

## Como o plugin se estrutura no disco

| Caminho | Localização |
|---|---|
| git clone (skill) | `~/.claude/skills/pagou-pix-integrator/` |
| /plugin (Unix) | `~/.claude/plugins/marketplaces/pagou-pix-integrator/` |
| /plugin (Windows) | `%USERPROFILE%\.claude\plugins\marketplaces\pagou-pix-integrator\` |

No caminho `/plugin`, a CLI também regista o plugin em `~/.claude/settings.json` na chave `enabledPlugins`.

---

## Onde o plugin atua

O plugin **não** modifica nada na tua máquina ou na pasta `~/.claude/`. Ele apenas é carregado pelo Claude Code quando invocas `/pagou-pix-integrator` dentro de um projeto.

Todo o trabalho efetivo da Skill acontece **no projeto-alvo** onde a invocas:

- Lê os ficheiros do projeto (descoberta)
- Gera código no projeto (cliente Pagou, endpoint, webhook, testes)
- Cria relatórios no projeto (PLAN, REPORT, SCORE, TEST_REPORT)

A Skill em si é apenas um conjunto de instruções, templates e código adapter.
