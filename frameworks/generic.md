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
(sem auth de sessão; protegido por verificação HMAC)
```

#### Verificação HMAC

```pseudo
verify_signature(raw_body, header_signature) -> bool
  secret = env("PAGOU_WEBHOOK_SECRET")
  if secret is empty:
      if env("PAGOU_ENV") == "production":
          raise "PAGOU_WEBHOOK_SECRET required in production"
      log_warn("signature check skipped in dev")
      return true
  if header_signature is empty:
      return false

  expected = HMAC_SHA256(raw_body, secret).hex()
  received = strip_prefix(header_signature, "sha256=")

  return constant_time_compare(expected, received)
```

**Equivalentes por linguagem:**

| Linguagem | HMAC | Comparação constante |
|---|---|---|
| Node | `crypto.createHmac('sha256',k).update(b).digest('hex')` | `crypto.timingSafeEqual(Buffer,Buffer)` |
| PHP | `hash_hmac('sha256',b,k)` | `hash_equals(a,b)` |
| Python | `hmac.new(k.encode(),b,'sha256').hexdigest()` | `hmac.compare_digest(a,b)` |
| Ruby | `OpenSSL::HMAC.hexdigest('SHA256',k,b)` | `Rack::Utils.secure_compare(a,b)` |
| Go | `hmac.New(sha256.New,k); h.Write(b); hex.EncodeToString(h.Sum(nil))` | `hmac.Equal([]byte(a),[]byte(b))` |
| .NET | `new HMACSHA256(k).ComputeHash(b)` → hex | `CryptographicOperations.FixedTimeEquals(a,b)` |

Pseudocódigo do handler (dedupe por `event.id` top-level):

```pseudo
handler(req):
    raw_body  = req.raw_body
    signature = req.header("X-Pagou-Signature")

    if not verify_signature(raw_body, signature):
        return 401 { error: "invalid signature" }

    body = parse_json(raw_body)

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

### Cancelar PIX pendente

```pseudo
cancel(transaction_id):
    resp = pagou_request("POST", "/v2/transactions/" + transaction_id + "/cancel")
    UPDATE pagou_pix_transactions SET status = resp.status WHERE pagou_transaction_id = transaction_id
    # NÃO mover order para cancelado aqui — esperar webhook transaction.cancelled
    audit_log("pagou.cancel.requested", { transaction_id, admin_user_id })
    return resp
```

Expor como endpoint admin: `POST /admin/pagou/transactions/:id/cancel`, autenticado.

### Refund (estorno)

```pseudo
refund(transaction_id, amount_cents?, reason?):
    body = {}
    if amount_cents:
        body.amount = amount_cents
    if reason:
        body.reason = reason

    resp = pagou_request("POST", "/v2/transactions/" + transaction_id + "/refund", body)
    UPDATE pagou_pix_transactions SET status = resp.status WHERE pagou_transaction_id = transaction_id
    # Estorno real confirma-se via webhook transaction.refunded
    audit_log("pagou.refund.requested", { transaction_id, admin_user_id, amount_cents, reason })
    return resp
```

Expor como endpoint admin: `POST /admin/pagou/transactions/:id/refund`, autenticado.

| Cenário | Comportamento |
|---|---|
| `amount_cents` omitido | Estorno total |
| `amount_cents` < total | Estorno parcial (cuidado: alguns provedores não permitem múltiplos parciais) |
| Transação ainda pending | API rejeita — usar cancel em vez disso |
| Após janela de 180 dias | API rejeita — fora do prazo |

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

## Frontend — princípios universais

Independente do stack, o frontend faz **exactamente** três coisas:

1. **Chamar o teu backend** para criar a cobrança (`POST /api/pagou/pix`)
2. **Renderizar o QR** retornado:

   ```html
   <!-- ⚠️ A Pagou devolve base64 SEM prefixo MIME. Sempre adicionar: -->
   <img src="data:image/png;base64,{pix_qr_code}" />
   ```

3. **Fazer polling do estado INTERNO do pedido**, **NÃO** da API Pagou:

   ```pseudo
   setInterval(() => {
       order = fetch("/api/orders/" + orderId + "/status")
       if order.status == "pago":
           clearInterval()
           showSuccess()
   }, 3000)
   ```

**Anti-padrões frequentes (rejeitar):**

| ❌ Errado | ✓ Correto |
|---|---|
| `fetch("https://api.pagou.ai/...")` direto do browser | Browser nunca chama Pagou direto — só o backend |
| `<img src="{base64}">` sem prefixo | `<img src="data:image/png;base64,{base64}">` |
| Polling do `/v2/transactions/{id}` da Pagou | Polling do `/api/orders/{id}/status` interno |
| Marcar UX como "pago" no `onSuccess` do POST inicial | Esperar status interno virar `pago` (webhook confirmou) |
| Polling sem clear ao desmontar componente | Sempre limpar interval no unmount/cleanup |

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
