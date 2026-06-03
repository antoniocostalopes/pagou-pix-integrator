# Prompt — Missing Data (Fim da Fase 1)

**Objetivo:** pedir ao usuário **apenas o que não foi possível inferir**, e nada mais.

## Os 4 dados permitidos

A Skill **só** pode pedir:

1. `PAGOU_API_KEY`
2. Modo de confirmação de pagamento — `webhook` (recomendado) ou `polling`
3. URL pública do projeto (para registrar o webhook) — **só** se modo = webhook
4. Status internos desejados

**Tudo o resto deve ter sido descoberto.** Se você está prestes a perguntar framework, banco, tabela, ORM, auth — pare e volte a `project-discovery.md` / `architecture-discovery.md`.

> **Apenas produção (desde v3.0.0):** a Skill chama sempre `https://api.pagou.ai`. **Não há pergunta de ambiente.** Para dev local sem tocar em produção, ver `tools/pagou-mock/` no repo da Skill.

## Template de mensagem ao usuário

> Antes de seguir, preciso de 4 dados que não consigo inferir do projeto:
>
> 1. **`PAGOU_API_KEY`** — chave de **produção** da sua conta Pagou (não cole se preferir definir você mesmo no `.env` depois). A Skill chama `https://api.pagou.ai` directamente — não há modo sandbox.
> 2. **Modo de confirmação de pagamento** — qual prefere?
>    - **`webhook`** (recomendado) — eventos em tempo real, robusto contra cliente fechar o browser, chargebacks tardios e refunds manuais. Requer URL pública + 2 min de registo no painel da Pagou.
>    - **`polling`** — sem URL pública, sem painel. Background poller pergunta à Pagou periodicamente. Mais simples; perde eventos tardios e tem latência maior. Bom para MVP / volume baixo / sem URL pública (intranet, dev local).
> 3. **URL pública** do projeto (ex.: `https://app.exemplo.com`) — só preciso se escolheu `webhook` no passo 2. Usada para registrar o webhook na Pagou.
> 4. **Status internos** — como você quer mapear os status do PIX? Sugestões padrão:
>
>    | Pagou | Sugerido |
>    |---|---|
>    | `pending` | `aguardando_pagamento` |
>    | `paid` | `pago` |
>    | `expired` | `expirado` |
>    | `canceled` | `cancelado` |
>    | `refused` | `recusado` |
>    | `refunded` | `estornado` |
>    | `partially_refunded` | `estornado_parcial` |
>    | `chargedback` | `chargeback` |
>
>    Quer ajustar algum?

## Regras de aceitação

### Sobre `PAGOU_API_KEY`

- Aceitar a chave inline OU instruir o usuário a defini-la em `.env` depois — **nunca** persistir em arquivos rastreados pelo Git
- Validar formato visual mínimo (string não vazia, sem espaços) — não validar contra a API nesta fase
- **Nunca** ecoar a chave em respostas, logs, ou comentários de código
- **Lembrar o utilizador:** esta é a chave de **produção**. Para testes locais, usar `tools/pagou-mock/` em vez de criar transações reais

### Sobre modo de confirmação

- **Default = `webhook`** — se o utilizador só carregar Enter ou disser "recomendado", assumir webhook
- Aceitar respostas equivalentes: `webhook` / `w` / `recomendado` / `1` → webhook; `polling` / `p` / `2` / `só polling` / `sem webhook` → polling
- Salvar em `PAGOU_CONFIRMATION_MODE` (`webhook` | `polling`)
- Se escolher `polling`, **pular a pergunta da URL pública** (não é necessária — não há nada para registar na Pagou)
- Se escolher `polling`, lembrar o utilizador no relatório final que pode mudar para webhook depois (o endpoint é sempre gerado em ambos os modos)

### Sobre URL pública

- **Só perguntar se modo = webhook**
- Aceitar apenas https:// (HTTP só permitido para `localhost`/`127.0.0.1` — útil em dev local com tunnel mas exibir warning)
- Verificar formato com regex simples
- Se desconhecida, **não bloquear** a implementação — registrar `<PUBLIC_URL_PENDING>` no `.env.example` e documentar no `README_PAGOU_PIX.md`

### Sobre status internos

- Default = mapeamento da tabela acima
- Se o usuário disser "use os mesmos do meu sistema atual" — descobrir do projeto (procurar enums ou tabelas com status de pedido) e propor

## O que **nunca** perguntar

| ❌ Não perguntar | ✓ Como obter |
|---|---|
| "Sandbox ou produção?" | **Não existe sandbox na v3+.** A Skill só fala com `https://api.pagou.ai` |
| "Qual URL da API Pagou?" | Hardcoded: `https://api.pagou.ai`. Nunca configurável |
| "Qual framework?" | Ler `package.json` / `composer.json` |
| "Qual banco?" | Ler `.env` (`DB_*`, `DATABASE_URL`) ou config |
| "Onde está o checkout?" | Grepar `checkout\|order\|pedido` |
| "Qual a tabela de pedidos?" | Ler models/migrations |
| "Qual auth você usa?" | Ler dependências e configs |
| "Onde devo criar os arquivos?" | Decidido em `architecture-discovery.md` |
| "Quer testes?" | Sim, sempre — gerar conforme convenção do projeto |
| "Quer reconciliação?" | Sim, sempre — em ambos os modos (frequência muda: horário em webhook, 15 min em polling) |

## Forma da pergunta

Use a `AskUserQuestion` tool quando disponível, com no máximo 4 perguntas (uma por dado). Senão, mensagem markdown corrida com numeração clara.

Sugestão de ordem para minimizar fricção: 1 (key) → 2 (modo) → 3 (URL, só se webhook) → 4 (status). Assim a URL só aparece quando faz sentido.
