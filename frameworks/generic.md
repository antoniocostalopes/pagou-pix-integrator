# Adapter — Genérico

Usar quando o projeto **não for** Next.js, Laravel, WordPress nem WooCommerce. Cobre Express/Fastify (Node), Django/FastAPI (Python), Rails (Ruby), Go (chi/gin/fiber), .NET, etc.

## Algoritmo de adaptação

1. **Identificar stack** lendo `package.json` / `requirements.txt` / `pyproject.toml` / `Gemfile` / `go.mod` / `*.csproj`
2. **Identificar ORM/driver**: Sequelize/Drizzle/TypeORM, SQLAlchemy/Django ORM, ActiveRecord, GORM, EF Core, ou SQL cru
3. **Identificar padrão de roteamento** (Express, FastAPI, Rails, chi, etc.)
4. **Aplicar o template universal** abaixo, traduzido para a linguagem/framework detectado

## Template universal — contrato de cada componente

### Configuração (env)

```
PAGOU_API_KEY=
PAGOU_ENV=sandbox            # sandbox | production
PAGOU_BASE_URL=              # opcional
```

Resolver base URL:

| `PAGOU_ENV` | Base URL |
|---|---|
| `sandbox` | `https://api-sandbox.pagou.ai` |
| `production` | `https://api.pagou.ai` |

### Cliente HTTP

Contrato mínimo:

```pseudo
function pagou_request(method, path, body?) -> json
  url      = base_url + path
  headers  = { Authorization: "Bearer " + api_key,
               Content-Type: "application/json",
               Accept:       "application/json" }
  response = HTTP.request(method, url, headers, body)
  if response.status >= 400:
      raise PagouError(response.status, response.body)
  return parse_json(response.body)
```

Sempre:

- Timeout ≤ 15 segundos
- Retornar resposta crua quando útil (para gravar `raw_response`)
- Nunca logar `Authorization` header

### Tabelas (qualquer banco SQL)

```sql
CREATE TABLE pagou_pix_transactions (
  id                   BIGSERIAL PRIMARY KEY,
  pagou_transaction_id VARCHAR(64)  NOT NULL UNIQUE,
  external_ref         VARCHAR(128) NOT NULL UNIQUE,
  order_id             VARCHAR(128) NOT NULL,
  amount_cents         INTEGER      NOT NULL,
  currency             CHAR(3)      NOT NULL DEFAULT 'BRL',
  status               VARCHAR(32)  NOT NULL,
  pix_qr_code          TEXT,
  pix_code             TEXT,
  raw_response         JSONB,
  created_at           TIMESTAMP    NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMP    NOT NULL DEFAULT NOW()
);
CREATE INDEX ix_pix_status ON pagou_pix_transactions(status);
CREATE INDEX ix_pix_order  ON pagou_pix_transactions(order_id);

CREATE TABLE pagou_webhook_events (
  id             BIGSERIAL PRIMARY KEY,
  event_id       VARCHAR(128) NOT NULL UNIQUE,
  event_type     VARCHAR(64)  NOT NULL,
  resource_id    VARCHAR(64),
  correlation_id VARCHAR(128),
  payload        JSONB        NOT NULL,
  processed_at   TIMESTAMP,
  created_at     TIMESTAMP    NOT NULL DEFAULT NOW()
);
CREATE INDEX ix_ev_type     ON pagou_webhook_events(event_type);
CREATE INDEX ix_ev_resource ON pagou_webhook_events(resource_id);
```

Para MySQL/MariaDB use `BIGINT UNSIGNED AUTO_INCREMENT`, `JSON` em vez de `JSONB`, e `DATETIME` em vez de `TIMESTAMP`.

### Endpoint — criar cobrança PIX

Contrato:

```
POST /api/pagou/pix
Authorization: <session do projeto>
Body:
  { "order_id": "..." }

Response 200:
  {
    "transaction_id": "tr_...",
    "status": "pending",
    "pix_qr_code": "<base64>",
    "pix_code": "<copia-e-cola>"
  }
```

Pseudocódigo:

```pseudo
handler(req):
    order_id = req.body.order_id
    order    = repo.find_order(order_id) or 404

    resp = pagou_request("POST", "/v2/transactions", {
        external_ref: order.id,
        amount:       order.amount_cents,
        currency:     "BRL",
        method:       "pix",
        buyer:        { name, email, document: { type, number } }
    })

    upsert pagou_pix_transactions
        on conflict(external_ref) update
        set status, pix_*, raw_response

    return 200 { transaction_id: resp.id, status, pix_qr_code, pix_code }
```

### Webhook handler

```
POST /webhooks/pagou
(sem auth de sessão; idealmente atrás de validação de IP/HMAC se Pagou suportar)
```

Pseudocódigo (escolha que segue PRD — dedupe por `event.id` top-level):

```pseudo
handler(req):
    body = parse_json(req.body)

    if body.event != "transaction" or not body.id:
        return 200 { received: true }

    try:
        INSERT INTO pagou_webhook_events
          (event_id, event_type, resource_id, correlation_id, payload)
          VALUES (body.id, body.data.event_type, body.data.id, body.data.correlation_id, body)
    catch UniqueViolation:
        # já recebido — idempotente
        return 200 { received: true }

    enqueue_async(process_event_job, body.id)

    return 200 { received: true }


process_event_job(event_id):
    ev = SELECT * FROM pagou_webhook_events WHERE event_id = event_id
    if ev.processed_at: return

    data = ev.payload.data

    UPDATE pagou_pix_transactions
       SET status = data.status, updated_at = NOW()
       WHERE pagou_transaction_id = data.id

    if data.event_type == "transaction.paid":
        UPDATE orders
           SET status = map_status("paid")
           WHERE id = data.correlation_id

    UPDATE pagou_webhook_events
       SET processed_at = NOW()
       WHERE event_id = ev.event_id
```

### Status map

```
pending             → aguardando_pagamento
paid                → pago
expired             → expirado
canceled            → cancelado
refused             → recusado
refunded            → estornado
partially_refunded  → estornado_parcial
chargedback         → chargeback
```

Substituir os valores internos conforme o domínio do projeto-alvo (usar os status que o usuário fornecer na fase de descoberta).

### Reconciliação

```pseudo
reconcile(transaction_id):
    resp = pagou_request("GET", "/v2/transactions/" + transaction_id)
    UPDATE pagou_pix_transactions SET status = resp.status, raw_response = resp WHERE pagou_transaction_id = transaction_id
    if resp.status == "paid":
        UPDATE orders SET status = "pago" WHERE id = resp.external_ref
```

Agendar como job noturno ou expor endpoint admin `POST /admin/pagou/reconcile/:id`.

### Testes

Padrões mínimos:

1. **Unit** — `mapStatus` para todos os 8 status conhecidos + 1 desconhecido
2. **Unit** — cálculo de `amount_cents` (multiplicação por 100, sem erro de ponto flutuante)
3. **Integration** — cliente Pagou com `nock`/`responses`/`vcr`/`httpmock` validando headers e payload
4. **Webhook** — POST do mesmo `event.id` duas vezes; segunda chamada é no-op
5. **Webhook** — POST de `transaction.paid` atualiza order para status interno correto
6. **E2E** — fluxo completo: criar cobrança via endpoint → simular webhook → ler order final

## Saídas obrigatórias

Independente do stack:

- Código source-controlled (não usar `eval` ou geração runtime de classes)
- `.env.example` com placeholders
- Migração rastreável (versionada)
- Testes executáveis com um comando único do projeto (`npm test`, `pytest`, `bundle exec rspec`, `go test ./...`, `dotnet test`)
- Documentação operacional em `README_PAGOU_PIX.md`

## Estratégia de assíncrono por stack

| Stack | Como processar webhook async |
|---|---|
| Express/Fastify | BullMQ, `setImmediate` para POC, fila Redis em prod |
| Django | Celery |
| FastAPI | `BackgroundTasks` para POC, Celery/Arq em prod |
| Rails | Sidekiq |
| Go | goroutine + canal limitado + persist em outbox |
| .NET | Hosted background services + channel ou MassTransit |

Se o projeto não tem fila e o tráfego é baixo, retornar 200 ao webhook e processar inline desde que < 5s. Documentar a limitação no `PAGOU_PIX_INTEGRATION_REPORT.md`.
