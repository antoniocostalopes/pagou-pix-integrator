# Prompt — Missing Data (Fim da Fase 1)

**Objetivo:** pedir ao usuário **apenas o que não foi possível inferir**, e nada mais.

## Os 4 dados permitidos

A Skill **só** pode pedir:

1. `PAGOU_API_KEY`
2. Ambiente — sandbox ou produção
3. URL pública do projeto (para registrar o webhook)
4. Status internos desejados

**Tudo o resto deve ter sido descoberto.** Se você está prestes a perguntar framework, banco, tabela, ORM, auth — pare e volte a `project-discovery.md` / `architecture-discovery.md`.

## Template de mensagem ao usuário

> Antes de seguir, preciso de 4 dados que não consigo inferir do projeto:
>
> 1. **`PAGOU_API_KEY`** — chave da sua conta Pagou (não cole se preferir definir você mesmo no `.env` depois).
> 2. **Ambiente** — sandbox ou produção?
> 3. **URL pública** do projeto (ex.: `https://app.exemplo.com`) — usada para registrar o webhook na Pagou.
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

### Sobre ambiente

- `sandbox` é o default seguro — só usar `production` com confirmação explícita
- Salvar em `PAGOU_ENV`

### Sobre URL pública

- Aceitar apenas https:// (HTTP só permitido para `localhost`/`127.0.0.1` em sandbox)
- Verificar formato com regex simples
- Se desconhecida, **não bloquear** a implementação — registrar `<PUBLIC_URL_PENDING>` no `.env.example` e documentar no `README_PAGOU_PIX.md`

### Sobre status internos

- Default = mapeamento da tabela acima
- Se o usuário disser "use os mesmos do meu sistema atual" — descobrir do projeto (procurar enums ou tabelas com status de pedido) e propor

## O que **nunca** perguntar

| ❌ Não perguntar | ✓ Como obter |
|---|---|
| "Qual framework?" | Ler `package.json` / `composer.json` |
| "Qual banco?" | Ler `.env` (`DB_*`, `DATABASE_URL`) ou config |
| "Onde está o checkout?" | Grepar `checkout|order|pedido` |
| "Qual a tabela de pedidos?" | Ler models/migrations |
| "Qual auth você usa?" | Ler dependências e configs |
| "Onde devo criar os arquivos?" | Decidido em `architecture-discovery.md` |
| "Quer testes?" | Sim, sempre — gerar conforme convenção do projeto |
| "Quer webhook?" | Sim, sempre — obrigatório no PRD |
| "Quer reconciliação?" | Sim, sempre — obrigatório no PRD |

## Forma da pergunta

Use a `AskUserQuestion` tool quando disponível, com no máximo 4 perguntas (uma por dado). Senão, mensagem markdown corrida com numeração clara.
