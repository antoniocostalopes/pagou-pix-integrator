# Instalação — Pagou PIX Integrator

Esta Skill é um pacote para o **Claude Code**. Pode ser instalada em três modos:

| Modo | Quando usar | Comando |
|---|---|---|
| **Global (recomendado)** | Você quer a skill disponível em qualquer projeto | scripts `install.ps1` / `install.sh` |
| **Por projeto** | Você quer a skill apenas no projeto X | copiar a pasta para `<projeto>/.claude/skills/pagou-pix-integrator` |
| **Symlink (dev)** | Você está desenvolvendo / editando a Skill | scripts com flag `-Link` (PowerShell) ou `--link` (bash) |

## Pré-requisitos

- Claude Code CLI instalado e funcionando (`claude --version`)
- PowerShell 5.1+ (Windows) ou Bash 4+ (macOS / Linux / WSL)

## Instalação rápida — Global

### Windows (PowerShell)

```powershell
cd "C:\caminho\até\pagou-pix-integrator"
.\install.ps1
```

Por padrão, copia a pasta para `$env:USERPROFILE\.claude\skills\pagou-pix-integrator`.

Para criar um link simbólico (recomendado se estiver editando a Skill):

```powershell
.\install.ps1 -Link
```

Symlinks no Windows requerem privilégios de administrador OU Developer Mode ativado.

### macOS / Linux (Bash)

```bash
cd /caminho/até/pagou-pix-integrator
chmod +x install.sh
./install.sh
```

Por padrão, copia para `~/.claude/skills/pagou-pix-integrator`.

Symlink:

```bash
./install.sh --link
```

## Verificação

Após instalar:

```bash
ls ~/.claude/skills/pagou-pix-integrator       # Unix
dir $env:USERPROFILE\.claude\skills\pagou-pix-integrator   # Windows
```

Reinicie o Claude Code (ou rode `/help` numa nova sessão) — a Skill deve aparecer como invocável:

```
/pagou-pix-integrator
```

## Instalação por projeto

Se preferir instalar apenas num projeto específico:

```bash
# Dentro do projeto onde quer ter PIX
mkdir -p .claude/skills
cp -r /caminho/até/pagou-pix-integrator .claude/skills/
```

```powershell
# Windows
New-Item -ItemType Directory -Force .claude\skills | Out-Null
Copy-Item -Recurse "C:\caminho\até\pagou-pix-integrator" .claude\skills\
```

A Skill ficará disponível apenas dentro daquele projeto.

## Uso

Dentro de um projeto onde você quer adicionar PIX, no Claude Code:

```
/pagou-pix-integrator
```

Ou simplesmente peça:

> "Integra PIX via Pagou.ai neste projeto."

A Skill executa autonomamente as 6 fases:

1. **Descobrir** — analisa o projeto sem perguntar
2. **Confirmar** — apresenta plano e pede aprovação
3. **Implementar** — gera código, migrations, testes
4. **Testar** — executa todos os testes
5. **Validar** — percorre 5 checklists
6. **Pontuar** — score 0–100 e classificação

Após concluir, a Skill grava no seu projeto:

- `PAGOU_PIX_INTEGRATION_PLAN.md`
- `PAGOU_PIX_INTEGRATION_REPORT.md`
- `PAGOU_PIX_INTEGRATION_SCORE.md`
- `README_PAGOU_PIX.md`
- `TEST_REPORT.md`

Mais o código real: cliente, serviço, endpoint, webhook, persistência.

## Atualizar

### Via cópia

Remova a versão antiga e instale a nova:

```bash
rm -rf ~/.claude/skills/pagou-pix-integrator
./install.sh
```

```powershell
Remove-Item -Recurse -Force $env:USERPROFILE\.claude\skills\pagou-pix-integrator
.\install.ps1
```

### Via symlink

Se instalou com `-Link` / `--link`, basta dar `git pull` (ou atualizar os ficheiros) no folder de origem — a Skill atualiza automaticamente.

## Desinstalar

```bash
rm -rf ~/.claude/skills/pagou-pix-integrator
```

```powershell
Remove-Item -Recurse -Force $env:USERPROFILE\.claude\skills\pagou-pix-integrator
```

## Resolução de problemas

### A Skill não aparece como invocável

1. Confirme que o folder destino existe: `~/.claude/skills/pagou-pix-integrator`
2. Confirme que `SKILL.md` está na raiz desse folder e começa com frontmatter `---` válido
3. Reinicie o Claude Code (fechar e abrir o terminal)
4. Tente listar com `/help` ou `/`

### "Symlink requer permissões" no Windows

Ative o **Developer Mode** em Configurações do Windows → Para Desenvolvedores → Modo de Desenvolvedor. Alternativamente, rode o PowerShell como Administrador.

### "Skill já instalada" mas comportamento desatualizado

Pode ser cache. Force a re-instalação:

```bash
./install.sh --force
```

```powershell
.\install.ps1 -Force
```

## Onde a Skill procura coisas

Após instalada, a Skill **não** modifica nada no `~/.claude/`. Ela apenas é lida pelo Claude Code quando você invoca `/pagou-pix-integrator` dentro de um projeto.

Todo o trabalho efetivo da Skill acontece **no projeto-alvo** onde você a invoca:

- Lê os ficheiros do projeto (discovery)
- Gera código no projeto
- Cria relatórios no projeto
- Executa testes no projeto

A Skill em si é apenas um conjunto de instruções e templates.
