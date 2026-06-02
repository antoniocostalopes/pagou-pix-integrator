# Adapter — Laravel

## Detecção

| Sinal | Verificar |
|---|---|
| `composer.json` contém `"laravel/framework"` | obrigatório |
| `artisan` na raiz | obrigatório |
| `app/Models/` (Eloquent) | usar Eloquent |
| `database/migrations/` | onde gerar migration |

## Variantes

- Laravel 10+ recomendado — sintaxe abaixo é compatível com 9, 10, 11
- Se houver Filament/Nova, registrar resources após a integração funcionar

---

## 1. Variáveis de ambiente

`.env`:

```bash
PAGOU_API_KEY=
PAGOU_ENV=sandbox
PAGOU_BASE_URL=
APP_PUBLIC_URL=https://example.com
```

`config/services.php` — acrescentar:

```php
'pagou' => [
    'key'      => env('PAGOU_API_KEY'),
    'env'      => env('PAGOU_ENV', 'sandbox'),
    'base_url' => env('PAGOU_BASE_URL'),
],
```

## 2. Migration

`database/migrations/2026_06_02_000000_create_pagou_pix_tables.php`:

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('pagou_pix_transactions', function (Blueprint $t) {
            $t->id();
            $t->string('pagou_transaction_id')->unique();
            $t->string('external_ref')->unique();
            $t->unsignedBigInteger('order_id');
            $t->unsignedInteger('amount_cents');
            $t->string('currency', 3)->default('BRL');
            $t->string('status');
            $t->text('pix_qr_code')->nullable();
            $t->text('pix_code')->nullable();
            $t->json('raw_response')->nullable();
            $t->timestamps();
            $t->index('order_id');
            $t->index('status');
        });

        Schema::create('pagou_webhook_events', function (Blueprint $t) {
            $t->id();
            $t->string('event_id')->unique();
            $t->string('event_type');
            $t->string('resource_id')->nullable();
            $t->string('correlation_id')->nullable();
            $t->json('payload');
            $t->timestamp('processed_at')->nullable();
            $t->timestamps();
            $t->index('event_type');
            $t->index('resource_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('pagou_webhook_events');
        Schema::dropIfExists('pagou_pix_transactions');
    }
};
```

Rodar:

```bash
php artisan migrate
```

## 3. Cliente Pagou

`app/Services/Pagou/PagouClient.php`:

```php
<?php

namespace App\Services\Pagou;

use Illuminate\Http\Client\Response;
use Illuminate\Support\Facades\Http;

class PagouClient
{
    private const BASE_URL = [
        'sandbox'    => 'https://api-sandbox.pagou.ai',
        'production' => 'https://api.pagou.ai',
    ];

    public function __construct(
        private ?string $apiKey = null,
        private ?string $env = null,
        private ?string $baseUrl = null,
    ) {
        $this->apiKey  ??= config('services.pagou.key');
        $this->env     ??= config('services.pagou.env', 'sandbox');
        $this->baseUrl ??= config('services.pagou.base_url') ?: self::BASE_URL[$this->env];

        if (empty($this->apiKey)) {
            throw new \RuntimeException('PAGOU_API_KEY is not set');
        }
    }

    public function post(string $path, array $body): array
    {
        return $this->handle(Http::withToken($this->apiKey)
            ->acceptJson()
            ->asJson()
            ->post($this->baseUrl . $path, $body));
    }

    public function get(string $path): array
    {
        return $this->handle(Http::withToken($this->apiKey)
            ->acceptJson()
            ->get($this->baseUrl . $path));
    }

    private function handle(Response $res): array
    {
        if (! $res->successful()) {
            throw new PagouException(
                "Pagou API error {$res->status()}",
                $res->status(),
                $res->json() ?? [],
            );
        }
        return $res->json() ?? [];
    }
}
```

`app/Services/Pagou/PagouException.php`:

```php
<?php

namespace App\Services\Pagou;

class PagouException extends \RuntimeException
{
    public function __construct(string $message, public int $status, public array $body = [])
    {
        parent::__construct($message);
    }
}
```

## 4. Serviço PIX

`app/Services/Pagou/PixService.php`:

```php
<?php

namespace App\Services\Pagou;

use App\Models\PagouPixTransaction;
use App\Models\Order;

class PixService
{
    public function __construct(private PagouClient $client) {}

    public function createCharge(Order $order): PagouPixTransaction
    {
        $resp = $this->client->post('/v2/transactions', [
            'external_ref' => (string) $order->id,
            'amount'       => $order->amount_cents,
            'currency'     => 'BRL',
            'method'       => 'pix',
            'buyer'        => [
                'name'     => $order->buyer_name,
                'email'    => $order->buyer_email,
                'document' => [
                    'type'   => 'CPF',
                    'number' => $order->buyer_document,
                ],
            ],
        ]);

        return PagouPixTransaction::updateOrCreate(
            ['external_ref' => (string) $order->id],
            [
                'pagou_transaction_id' => $resp['id'],
                'order_id'             => $order->id,
                'amount_cents'         => $order->amount_cents,
                'currency'             => 'BRL',
                'status'               => $resp['status'],
                'pix_qr_code'          => $resp['pix_qr_code'] ?? null,
                'pix_code'             => $resp['pix_code'] ?? null,
                'raw_response'         => $resp,
            ],
        );
    }

    public function refresh(string $transactionId): array
    {
        return $this->client->get("/v2/transactions/{$transactionId}");
    }
}
```

`app/Models/PagouPixTransaction.php`:

```php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class PagouPixTransaction extends Model
{
    protected $table = 'pagou_pix_transactions';
    protected $guarded = [];
    protected $casts = [
        'raw_response' => 'array',
        'amount_cents' => 'integer',
    ];
}
```

`app/Models/PagouWebhookEvent.php`:

```php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class PagouWebhookEvent extends Model
{
    protected $table = 'pagou_webhook_events';
    protected $guarded = [];
    protected $casts = ['payload' => 'array'];
}
```

## 5. Status mapping

`app/Services/Pagou/StatusMap.php`:

```php
<?php

namespace App\Services\Pagou;

class StatusMap
{
    public const MAP = [
        'pending'            => 'aguardando_pagamento',
        'paid'               => 'pago',
        'expired'            => 'expirado',
        'canceled'           => 'cancelado',
        'refused'            => 'recusado',
        'refunded'           => 'estornado',
        'partially_refunded' => 'estornado_parcial',
        'chargedback'        => 'chargeback',
    ];

    public static function toInternal(string $pagou): string
    {
        return self::MAP[$pagou] ?? 'desconhecido';
    }
}
```

## 6. Endpoints

`routes/api.php`:

```php
use App\Http\Controllers\PagouPixController;
use App\Http\Controllers\PagouWebhookController;

Route::middleware('auth:sanctum')->post('/pagou/pix', [PagouPixController::class, 'create']);
Route::post('/webhooks/pagou', [PagouWebhookController::class, 'handle'])
    ->withoutMiddleware(\App\Http\Middleware\VerifyCsrfToken::class);
```

`app/Http/Controllers/PagouPixController.php`:

```php
<?php

namespace App\Http\Controllers;

use App\Models\Order;
use App\Services\Pagou\PixService;
use Illuminate\Http\Request;

class PagouPixController extends Controller
{
    public function __construct(private PixService $service) {}

    public function create(Request $req)
    {
        $data = $req->validate(['order_id' => 'required|integer|exists:orders,id']);
        $order = Order::findOrFail($data['order_id']);
        $tx = $this->service->createCharge($order);

        return response()->json([
            'transaction_id' => $tx->pagou_transaction_id,
            'status'         => $tx->status,
            'pix_qr_code'    => $tx->pix_qr_code,
            'pix_code'       => $tx->pix_code,
        ]);
    }
}
```

## 7. Webhook

`app/Http/Controllers/PagouWebhookController.php`:

```php
<?php

namespace App\Http\Controllers;

use App\Jobs\ProcessPagouEvent;
use App\Models\PagouWebhookEvent;
use Illuminate\Http\Request;

class PagouWebhookController extends Controller
{
    public function handle(Request $req)
    {
        $payload = $req->json()->all();

        if (($payload['event'] ?? null) !== 'transaction' || empty($payload['id'])) {
            return response()->json(['received' => true]);
        }

        try {
            PagouWebhookEvent::create([
                'event_id'       => $payload['id'],
                'event_type'     => $payload['data']['event_type'] ?? 'unknown',
                'resource_id'    => $payload['data']['id'] ?? null,
                'correlation_id' => $payload['data']['correlation_id'] ?? null,
                'payload'        => $payload,
            ]);
        } catch (\Throwable $e) {
            return response()->json(['received' => true]);
        }

        ProcessPagouEvent::dispatch($payload['id']);

        return response()->json(['received' => true]);
    }
}
```

`app/Jobs/ProcessPagouEvent.php`:

```php
<?php

namespace App\Jobs;

use App\Models\Order;
use App\Models\PagouPixTransaction;
use App\Models\PagouWebhookEvent;
use App\Services\Pagou\StatusMap;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;

class ProcessPagouEvent implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public function __construct(public string $eventId) {}

    public function handle(): void
    {
        $event = PagouWebhookEvent::where('event_id', $this->eventId)->first();
        if (! $event || $event->processed_at) return;

        $data = $event->payload['data'] ?? [];
        $status = $data['status'] ?? null;
        $resourceId = $data['id'] ?? null;
        $correlationId = $data['correlation_id'] ?? null;

        if ($resourceId && $status) {
            PagouPixTransaction::where('pagou_transaction_id', $resourceId)
                ->update(['status' => $status]);
        }

        if (($data['event_type'] ?? '') === 'transaction.paid' && $correlationId) {
            Order::where('id', $correlationId)->update([
                'status' => StatusMap::toInternal('paid'),
            ]);
        }

        $event->update(['processed_at' => now()]);
    }
}
```

## 8. Testes (PHPUnit / Pest)

`tests/Feature/PagouWebhookTest.php`:

```php
<?php

use App\Models\PagouWebhookEvent;
use Illuminate\Foundation\Testing\RefreshDatabase;

uses(RefreshDatabase::class);

it('dedupes by event_id', function () {
    $payload = [
        'id'    => 'evt_pay_1001',
        'event' => 'transaction',
        'data'  => ['event_type' => 'transaction.paid', 'id' => 'tr_1', 'status' => 'paid'],
    ];

    $this->postJson('/api/webhooks/pagou', $payload)->assertOk();
    $this->postJson('/api/webhooks/pagou', $payload)->assertOk();

    expect(PagouWebhookEvent::where('event_id', 'evt_pay_1001')->count())->toBe(1);
});
```

`tests/Unit/StatusMapTest.php`:

```php
<?php

use App\Services\Pagou\StatusMap;

test('maps paid', fn () => expect(StatusMap::toInternal('paid'))->toBe('pago'));
test('handles unknown', fn () => expect(StatusMap::toInternal('alien'))->toBe('desconhecido'));
```

## 9. Verificação

```bash
php artisan migrate
php artisan test
php artisan route:list | grep pagou
```
