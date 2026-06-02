# Architecture — visão da Skill

Esta Skill é um **agente de integração** que opera em duas direções:

1. **Lê** o projeto-alvo para entender contexto
2. **Escreve** o código de integração PIX seguindo padrões existentes

## Componentes da Skill

```
┌──────────────────────────────────────────────────────────────┐
│                      Pagou PIX Integrator                     │
│                                                               │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐     │
│  │ SKILL.md │  │CLAUDE.md │  │KNOWLEDGE │  │ README   │     │
│  │ contrato │  │  regras  │  │  Pagou   │  │  humano  │     │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘     │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐    │
│  │                       prompts/                        │    │
│  │  discovery → plan → integration → validation → score │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐    │
│  │                     frameworks/                       │    │
│  │   nextjs · laravel · wordpress · woocommerce · generic│    │
│  │   (código pronto, específico por stack)              │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │  templates/  │  │  checklists/ │  │    docs/     │       │
│  │ 5 relatórios │  │ 5 categorias │  │ referência   │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
└──────────────────────────────────────────────────────────────┘
```

## Componentes que a Skill **gera** no projeto-alvo

```
                     ┌─────────────────────────┐
                     │       Frontend          │
                     │  (renderiza QR + code)  │
                     └────────────┬────────────┘
                                  │ POST /api/pagou/pix
                                  ▼
┌──────────────────────────────────────────────────────────────┐
│                         Backend                              │
│                                                              │
│  ┌──────────────────┐                                        │
│  │  HTTP Endpoint   │                                        │
│  │  POST /pagou/pix │──┐                                     │
│  └──────────────────┘  │                                     │
│                        │ orderId                             │
│                        ▼                                     │
│  ┌──────────────────────────────┐                            │
│  │       PixService.create      │                            │
│  └──────────┬───────────────────┘                            │
│             │                                                │
│             ▼                                                │
│  ┌──────────────────────────────┐                            │
│  │       PagouClient.post       │──────► POST /v2/transact.  │
│  └──────────────────────────────┘        Pagou.ai            │
│             │                                                │
│             ▼                                                │
│  ┌──────────────────────────────┐                            │
│  │  pagou_pix_transactions      │                            │
│  │  (upsert por external_ref)   │                            │
│  └──────────────────────────────┘                            │
│                                                              │
│  ────────────────────────────────────────────────────────    │
│                                                              │
│         Pagou.ai ──────► POST /webhooks/pagou                │
│                          │                                   │
│                          ▼                                   │
│              ┌──────────────────────┐                        │
│              │ Webhook Handler      │                        │
│              │ 1. Validar payload   │                        │
│              │ 2. INSERT event_id   │                        │
│              │    (UNIQUE = dedup)  │                        │
│              │ 3. Enqueue job       │                        │
│              │ 4. ACK rápido        │                        │
│              └──────┬───────────────┘                        │
│                     │                                        │
│                     ▼ async                                  │
│              ┌──────────────────────┐                        │
│              │ ProcessEvent Job     │                        │
│              │ - Update tx status   │                        │
│              │ - Update order       │                        │
│              │ - Mark processed_at  │                        │
│              └──────────────────────┘                        │
│                                                              │
│  ────────────────────────────────────────────────────────    │
│                                                              │
│  Cron noturno ──► reconcile(tx_id) ──► GET /v2/transact.     │
│                                          Pagou.ai            │
└──────────────────────────────────────────────────────────────┘
```

## Princípios de design

### Camadas

```
HTTP Endpoint   — validação de input, auth, resposta
   └─► Service  — regra de negócio, orquestração
       └─► Client — HTTP request, parsing, error handling
           └─► Pagou API
```

Cada camada faz **uma coisa**. Endpoint não sabe HTTP da Pagou; Service não sabe HTTP do framework; Client não sabe regras de negócio.

### Idempotência em 3 lugares

1. **Criação de cobrança** — upsert por `external_ref`
2. **Recepção de webhook** — UNIQUE em `event_id`
3. **Processamento de evento** — checar `processed_at`, UPDATE conditional

### Acoplamento mínimo ao projeto-alvo

- O código gerado **referencia** o modelo de pedido existente, mas **não** o modifica (apenas campo `status` se aprovado)
- Tabelas Pagou são separadas (`pagou_*`) — facilita remoção
- Status mapping é um arquivo isolado — fácil ajustar

### Resiliência

- Reconciliação cobre webhook perdido
- Dedup cobre webhook duplicado
- Upsert cobre re-tentativa de criação
- Logs estruturados cobrem auditoria

## Não-objetivos

- A Skill **não** implementa Pix Out (transfers)
- A Skill **não** implementa Subscriptions
- A Skill **não** implementa pagamento por cartão
- A Skill **não** registra webhook na Pagou automaticamente (escopo do painel)
- A Skill **não** reorganiza o projeto-alvo — apenas acrescenta

## Limites conhecidos

- Em ambientes serverless sem fila (Vercel free, Netlify free), processamento síncrono é a única opção — Skill documenta e usa, com warning no relatório
- Em projetos sem ORM, Skill cai para SQL cru via driver — pode parecer inconsistente com restante do código mas funciona
- Em frameworks muito exóticos (Phoenix, Hanami, Crystal), `frameworks/generic.md` cobre o contrato; código exato fica por conta do desenvolvedor com os hints da Skill
