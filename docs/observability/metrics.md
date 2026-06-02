# Observabilidade — Métricas

Definição das métricas que a integração PIX deve emitir. Formato compatível com **Prometheus / OpenTelemetry**, fácil de mapear para Datadog, New Relic, CloudWatch.

## Convenções

- Nome: `pagou_<area>_<metric>_<unit>` em snake_case
- Labels: baixa cardinalidade (`status`, `event_type`, `env`). **Nunca** `transaction_id` ou `event_id` (cardinalidade explode)
- Histogramas: usar `_seconds` para latência, `_bytes` para tamanho

## Métricas obrigatórias

### Cobranças

| Métrica | Tipo | Labels | Significado |
|---|---|---|---|
| `pagou_transactions_created_total` | Counter | `env`, `result` (`ok`/`error`) | Cobranças PIX criadas |
| `pagou_transaction_create_duration_seconds` | Histogram | `env` | Latência da chamada `POST /v2/transactions` |
| `pagou_transaction_amount_cents` | Histogram | `env` | Distribuição de valores cobrados |

### Webhooks

| Métrica | Tipo | Labels | Significado |
|---|---|---|---|
| `pagou_webhook_received_total` | Counter | `event_type` (`transaction.paid`, etc.) | Webhooks recebidos por tipo |
| `pagou_webhook_duplicate_total` | Counter | — | Eventos duplicados (UNIQUE conflict) |
| `pagou_webhook_invalid_signature_total` | Counter | — | Webhooks rejeitados por HMAC |
| `pagou_webhook_ack_duration_seconds` | Histogram | — | Tempo do handler até responder 200 (deve ser p95 < 1s) |
| `pagou_webhook_processing_duration_seconds` | Histogram | `event_type`, `result` | Tempo do job assíncrono |
| `pagou_webhook_processing_errors_total` | Counter | `event_type` | Erros no processamento |

### Reconciliação

| Métrica | Tipo | Labels | Significado |
|---|---|---|---|
| `pagou_reconcile_runs_total` | Counter | `trigger` (`cron`/`admin`/`webhook_retry`) | Reconciliações executadas |
| `pagou_reconcile_drift_total` | Counter | `from_status`, `to_status` | Quantas vezes a reconciliação encontrou divergência |
| `pagou_reconcile_pending_transactions` | Gauge | — | Transações em `pending` há mais de 1h |

### Refund/Cancel

| Métrica | Tipo | Labels | Significado |
|---|---|---|---|
| `pagou_refund_requests_total` | Counter | `result` (`ok`/`error`), `type` (`total`/`partial`) | Pedidos de estorno |
| `pagou_cancel_requests_total` | Counter | `result` (`ok`/`error`) | Pedidos de cancelamento |

### Saúde geral

| Métrica | Tipo | Labels | Significado |
|---|---|---|---|
| `pagou_api_request_errors_total` | Counter | `endpoint`, `status_code` | Erros 4xx/5xx da API Pagou |
| `pagou_api_request_duration_seconds` | Histogram | `endpoint` | Latência de chamadas à Pagou |

## Snippets por stack

### Next.js / Node.js (`prom-client`)

```ts
import { Counter, Histogram, register } from "prom-client";

export const txCreatedTotal = new Counter({
  name: "pagou_transactions_created_total",
  help: "PIX charges created",
  labelNames: ["env", "result"],
});

export const txCreateDuration = new Histogram({
  name: "pagou_transaction_create_duration_seconds",
  help: "POST /v2/transactions latency",
  labelNames: ["env"],
  buckets: [0.1, 0.25, 0.5, 1, 2.5, 5, 10],
});

export const webhookAckDuration = new Histogram({
  name: "pagou_webhook_ack_duration_seconds",
  help: "Webhook handler ACK time",
  buckets: [0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
});

// Expor em /api/metrics
export async function GET() {
  return new Response(await register.metrics(), {
    headers: { "Content-Type": register.contentType },
  });
}
```

### Laravel (`spatie/laravel-prometheus` ou `arquivei/laravel-prometheus`)

```php
// app/Providers/PagouMetricsProvider.php
use Prometheus\CollectorRegistry;

public function boot(CollectorRegistry $registry): void
{
    $registry->getOrRegisterCounter(
        'app', 'pagou_transactions_created_total',
        'PIX charges created', ['env', 'result']
    );
    // ...
}

// No PixService:
$counter = app(CollectorRegistry::class)
    ->getCounter('app', 'pagou_transactions_created_total');
$counter->inc([config('services.pagou.env'), 'ok']);
```

### Python (FastAPI / Django) (`prometheus-client`)

```python
from prometheus_client import Counter, Histogram

pagou_tx_created = Counter(
    "pagou_transactions_created_total",
    "PIX charges created",
    ["env", "result"],
)

pagou_webhook_ack = Histogram(
    "pagou_webhook_ack_duration_seconds",
    "Webhook handler ACK time",
    buckets=(0.05, 0.1, 0.25, 0.5, 1, 2.5, 5),
)
```

### Go (`prometheus/client_golang`)

```go
var (
    PagouTxCreated = promauto.NewCounterVec(prometheus.CounterOpts{
        Name: "pagou_transactions_created_total",
    }, []string{"env", "result"})
)
```

## Endpoint `/metrics`

Cada projeto deve expor `/metrics` (ou `/api/metrics`) atrás de auth (basic auth, IP allowlist, ou via service mesh / Prometheus federation).

**Nunca** expor `/metrics` pública sem auth — pode vazar informação sobre volume de transações.

## OpenTelemetry alternative

Se o projeto já usa OTel, mapear as mesmas métricas como `Counter`/`Histogram` no SDK respetivo e exportar para o backend escolhido (Tempo, Jaeger, Datadog).

```yaml
# resource attributes
service.name: pagou-pix-integrator
service.version: 1.2.0
deployment.environment: production
```
