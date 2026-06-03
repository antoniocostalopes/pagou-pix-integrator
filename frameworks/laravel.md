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
PAGOU_API_KEY=                       # chave de PRODUÇÃO (Skill v3+ não suporta sandbox)
PAGOU_WEBHOOK_SECRET=
PAGOU_CONFIRMATION_MODE=webhook      # webhook | polling
APP_PUBLIC_URL=https://example.com   # só relevante se modo = webhook
```

`config/services.php` — acrescentar:

```php
'pagou' => [
    'key' => env('PAGOU_API_KEY'),
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
    // v3.0.0+ — apenas produção
    private const BASE_URL = 'https://api.pagou.ai';

    public function __construct(
        private ?string $apiKey = null,
    ) {
        $this->apiKey ??= config('services.pagou.key');

        if (empty($this->apiKey)) {
            throw new \RuntimeException('PAGOU_API_KEY is not set');
        }
    }

    public function post(string $path, array $body): array
    {
        return $this->handle(Http::withToken($this->apiKey)
            ->acceptJson()
            ->asJson()
            ->post(self::BASE_URL . $path, $body));
    }

    public function get(string $path): array
    {
        return $this->handle(Http::withToken($this->apiKey)
            ->acceptJson()
            ->get(self::BASE_URL . $path));
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

    public function cancel(string $transactionId): array
    {
        return $this->client->post("/v2/transactions/{$transactionId}/cancel", []);
    }

    public function refund(string $transactionId, ?int $amountCents = null, ?string $reason = null): array
    {
        $body = array_filter([
            'amount' => $amountCents,
            'reason' => $reason,
        ], fn ($v) => $v !== null);

        return $this->client->post("/v2/transactions/{$transactionId}/refund", $body);
    }
}
```

## 7.1 Endpoints admin — cancel + refund

`routes/api.php`:

```php
Route::middleware(['auth:sanctum', 'can:manage-payments'])->group(function () {
    Route::post('/admin/pagou/transactions/{id}/cancel', [\App\Http\Controllers\PagouAdminController::class, 'cancel']);
    Route::post('/admin/pagou/transactions/{id}/refund', [\App\Http\Controllers\PagouAdminController::class, 'refund']);
});
```

`app/Http/Controllers/PagouAdminController.php`:

```php
<?php

namespace App\Http\Controllers;

use App\Models\PagouPixTransaction;
use App\Services\Pagou\PixService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class PagouAdminController extends Controller
{
    public function __construct(private PixService $service) {}

    public function cancel(string $id, Request $req)
    {
        try {
            $resp = $this->service->cancel($id);
            PagouPixTransaction::where('pagou_transaction_id', $id)
                ->update(['status' => $resp['status'] ?? 'canceled']);

            Log::info('pagou.cancel.requested', [
                'transaction_id' => $id,
                'admin_user_id'  => $req->user()->id,
            ]);

            return response()->json(['ok' => true, 'status' => $resp['status'] ?? null]);
        } catch (\Throwable $e) {
            Log::error('pagou.cancel.failed', ['transaction_id' => $id, 'error' => $e->getMessage()]);
            return response()->json(['error' => 'cancel failed'], 502);
        }
    }

    public function refund(string $id, Request $req)
    {
        $data = $req->validate([
            'amount_cents' => 'nullable|integer|min:1',
            'reason'       => 'nullable|string|max:255',
        ]);

        try {
            $resp = $this->service->refund($id, $data['amount_cents'] ?? null, $data['reason'] ?? null);
            PagouPixTransaction::where('pagou_transaction_id', $id)
                ->update(['status' => $resp['status'] ?? 'refunded']);

            Log::info('pagou.refund.requested', [
                'transaction_id' => $id,
                'admin_user_id'  => $req->user()->id,
                'amount_cents'   => $data['amount_cents'] ?? null,
                'reason'         => $data['reason'] ?? null,
            ]);

            return response()->json(['ok' => true, 'status' => $resp['status'] ?? null]);
        } catch (\Throwable $e) {
            Log::error('pagou.refund.failed', ['transaction_id' => $id, 'error' => $e->getMessage()]);
            return response()->json(['error' => 'refund failed'], 502);
        }
    }
}
```

> A confirmação real chega no webhook (`transaction.cancelled` / `.refunded` / `.partially_refunded`). O endpoint apenas dispara a ação e atualiza o status crú.

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

## 7. Webhook (com verificação HMAC)

`app/Services/Pagou/Signature.php`:

```php
<?php

namespace App\Services\Pagou;

class Signature
{
    public static function verify(string $rawBody, ?string $header): bool
    {
        $secret = config('services.pagou.webhook_secret');

        if (empty($secret)) {
            if (config('services.pagou.env') === 'production') {
                throw new \RuntimeException('PAGOU_WEBHOOK_SECRET is required in production');
            }
            \Log::warning('[pagou] PAGOU_WEBHOOK_SECRET not set — signature check skipped (dev only)');
            return true;
        }
        if (empty($header)) return false;

        $expected = hash_hmac('sha256', $rawBody, $secret);
        $received = preg_replace('/^sha256=/', '', $header);

        return hash_equals($expected, $received);
    }
}
```

Adicionar em `config/services.php`:

```php
'pagou' => [
    'key'            => env('PAGOU_API_KEY'),
    'webhook_secret' => env('PAGOU_WEBHOOK_SECRET'),
],
```

`app/Http/Controllers/PagouWebhookController.php`:

```php
<?php

namespace App\Http\Controllers;

use App\Jobs\ProcessPagouEvent;
use App\Models\PagouWebhookEvent;
use App\Services\Pagou\Signature;
use Illuminate\Http\Request;

class PagouWebhookController extends Controller
{
    public function handle(Request $req)
    {
        $rawBody = $req->getContent();
        $signature = $req->header('X-Pagou-Signature');

        if (! Signature::verify($rawBody, $signature)) {
            return response()->json(['error' => 'invalid signature'], 401);
        }

        $payload = json_decode($rawBody, true) ?? [];

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

## 9. Frontend

### Blade component

`resources/views/components/pagou-pix.blade.php`:

```blade
@props(['order'])

<div x-data="pagouPix({{ $order->id }})">
    <template x-if="state === 'idle'">
        <button @click="start" class="btn btn-primary">Pagar com PIX</button>
    </template>

    <template x-if="state === 'creating'">
        <p>A gerar QR Code…</p>
    </template>

    <template x-if="state === 'waiting'">
        <div>
            <h3>Pague com PIX</h3>
            {{-- ⚠️ Base64 sem prefixo MIME — adicionar manualmente --}}
            <img :src="'data:image/png;base64,' + qrCode" alt="PIX QR" style="width:280px">

            <p>Ou copia o código:</p>
            <textarea readonly x-text="pixCode" style="width:100%;height:80px"></textarea>
            <button @click="copy" x-text="copied ? '✓ Copiado' : 'Copiar PIX'"></button>

            <p>A verificar pagamento…</p>
        </div>
    </template>

    <template x-if="state === 'paid'">
        <p>✓ Pagamento confirmado!</p>
    </template>

    <template x-if="state === 'error'">
        <p style="color:red" x-text="'Erro: ' + errorMessage"></p>
    </template>
</div>

<script>
function pagouPix(orderId) {
    return {
        state: 'idle',
        qrCode: '',
        pixCode: '',
        copied: false,
        errorMessage: '',
        pollTimer: null,

        async start() {
            this.state = 'creating';
            const res = await fetch('/api/pagou/pix', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-TOKEN': document.querySelector('meta[name=csrf-token]')?.content,
                },
                body: JSON.stringify({ order_id: orderId }),
            });

            if (!res.ok) {
                this.state = 'error';
                this.errorMessage = `HTTP ${res.status}`;
                return;
            }

            const data = await res.json();
            this.qrCode = data.pix_qr_code;
            this.pixCode = data.pix_code;
            this.state = 'waiting';

            // Polling do estado interno do pedido (não da Pagou)
            this.pollTimer = setInterval(async () => {
                const r = await fetch(`/api/orders/${orderId}/status`);
                const o = await r.json();
                if (o.status === 'pago') {
                    clearInterval(this.pollTimer);
                    this.state = 'paid';
                }
            }, 3000);
        },

        copy() {
            navigator.clipboard.writeText(this.pixCode);
            this.copied = true;
            setTimeout(() => { this.copied = false; }, 2000);
        },
    };
}
</script>
```

Usar numa view Blade:

```blade
<x-pagou-pix :order="$order" />
```

> Para projetos com Livewire, criar `App\Livewire\PagouPix` com a mesma lógica server-side em vez de Alpine. O polling fica em `wire:poll.3s="checkStatus"`.

## 10. Verificação

```bash
php artisan migrate
php artisan test
php artisan route:list | grep pagou
```

---

## 11. Modo polling-only (v2.0.0+)

Aplicar **apenas se** o utilizador respondeu `polling` à 5ª pergunta.

### Background poller — Schedule task

`app/Console/Kernel.php`:

```php
protected function schedule(Schedule $schedule): void
{
    // Poller curto: cada minuto, transações pending dentro do TTL
    $schedule->command('pagou:poll')
             ->everyMinute()
             ->withoutOverlapping()
             ->runInBackground();

    // Reconciliação para eventos tardios: cada 15 min
    $schedule->command('pagou:reconcile-late')
             ->everyFifteenMinutes()
             ->withoutOverlapping();
}
```

### Comando `pagou:poll`

`app/Console/Commands/PagouPoll.php`:

```php
<?php
namespace App\Console\Commands;

use App\Models\PagouPixTransaction;
use App\Services\Pagou\PagouClient;
use App\Services\Pagou\StatusMapper;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class PagouPoll extends Command
{
    protected $signature = 'pagou:poll';
    protected $description = 'Polls Pagou for status of non-terminal PIX transactions';

    public function handle(PagouClient $pagou, StatusMapper $mapper): int
    {
        $candidates = PagouPixTransaction::query()
            ->whereIn('status', ['pending', 'created'])
            ->where('created_at', '>=', now()->subHour())
            ->limit(100)
            ->get();

        $checked = 0;
        $changed = 0;

        foreach ($candidates as $tx) {
            try {
                $remote = $pagou->get("/v2/transactions/{$tx->pagou_transaction_id}");
                $checked++;

                if ($remote['status'] === $tx->status) {
                    continue;
                }

                DB::transaction(function () use ($tx, $remote, $mapper) {
                    $tx->update(['status' => $remote['status'], 'updated_at' => now()]);

                    if (in_array($remote['status'], ['paid', 'expired', 'canceled', 'refused'])) {
                        \App\Models\Order::where('id', $tx->external_ref)
                            ->update(['status' => $mapper->internal($remote['status'])]);
                    }
                });

                $changed++;
            } catch (\Throwable $e) {
                logger()->warning('pagou.poll.error', ['tx' => $tx->id, 'error' => $e->getMessage()]);
            }
        }

        $this->info("Checked {$checked}, changed {$changed}");
        return self::SUCCESS;
    }
}
```

### Comando `pagou:reconcile-late`

Mesmo padrão mas a query procura transações **terminais** nos últimos 30 dias para apanhar `refunded`, `partially_refunded`, `chargedback`:

```php
PagouPixTransaction::query()
    ->whereIn('status', ['paid', 'expired', 'canceled'])
    ->where('created_at', '>=', now()->subDays(30))
    ->limit(200)
    ->get();
```

E na propagação ao pedido, lidar especificamente com os status pós-pagamento:

```php
if (in_array($remote['status'], ['refunded', 'partially_refunded', 'chargedback'])) {
    Order::where('id', $tx->external_ref)
        ->update(['status' => $mapper->internal($remote['status'])]);
}
```

### Limitações

- Custo: 100 transações × 1/min = 6 mil requests/h por hora de pico.
- Latência ≈ 30s–1min (mínimo do Laravel Schedule).
- `PAGOU_WEBHOOK_SECRET` continua opcional em modo polling. Endpoint webhook continua a existir mas nunca recebe tráfego.
