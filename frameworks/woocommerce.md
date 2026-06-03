# Adapter — WooCommerce

## Detecção

| Sinal | Verificar |
|---|---|
| Plugin `woocommerce/woocommerce.php` ativo | obrigatório |
| `wc()` global disponível | confirma WC carregado |
| Classe `WC_Payment_Gateway` existe | API de gateways |
| Tabela `wp_wc_orders` (HPOS) ou `wp_posts` com `shop_order` | onde os pedidos vivem |

A integração é entregue como um **gateway de pagamento** que aparece no checkout do WooCommerce.

---

## 1. Estrutura

```
wp-content/plugins/pagou-pix-wc/
├── pagou-pix-wc.php            ← bootstrap
├── includes/
│   ├── class-wc-pagou-gateway.php
│   ├── class-pagou-client.php
│   ├── class-webhook.php
│   ├── class-status-map.php
│   └── class-installer.php
├── assets/
│   └── pix.svg
└── uninstall.php
```

## 2. Bootstrap

`pagou-pix-wc.php`:

```php
<?php
/**
 * Plugin Name: Pagou PIX para WooCommerce
 * Description: Gateway PIX via Pagou.ai
 * Version: 1.0.0
 * WC requires at least: 7.0
 * Requires PHP: 8.0
 */

if (! defined('ABSPATH')) exit;

define('PAGOU_PIX_WC_DIR', plugin_dir_path(__FILE__));

require_once PAGOU_PIX_WC_DIR . 'includes/class-installer.php';
require_once PAGOU_PIX_WC_DIR . 'includes/class-status-map.php';
require_once PAGOU_PIX_WC_DIR . 'includes/class-pagou-client.php';
require_once PAGOU_PIX_WC_DIR . 'includes/class-webhook.php';

register_activation_hook(__FILE__, ['Pagou_Pix_WC_Installer', 'install']);

add_action('plugins_loaded', function () {
    if (! class_exists('WC_Payment_Gateway')) return;
    require_once PAGOU_PIX_WC_DIR . 'includes/class-wc-pagou-gateway.php';

    add_filter('woocommerce_payment_gateways', function ($gateways) {
        $gateways[] = 'WC_Pagou_Pix_Gateway';
        return $gateways;
    });
});

add_action('rest_api_init', function () {
    Pagou_Pix_WC_Webhook::register_routes();
});

// HPOS compatibility
add_action('before_woocommerce_init', function () {
    if (class_exists(\Automattic\WooCommerce\Utilities\FeaturesUtil::class)) {
        \Automattic\WooCommerce\Utilities\FeaturesUtil::declare_compatibility(
            'custom_order_tables', __FILE__, true
        );
    }
});
```

## 3. Installer (apenas tabela de eventos — pedidos já são do WC)

`includes/class-installer.php`:

```php
<?php
if (! defined('ABSPATH')) exit;

class Pagou_Pix_WC_Installer
{
    public static function install(): void
    {
        global $wpdb;
        $charset = $wpdb->get_charset_collate();
        $ev = $wpdb->prefix . 'pagou_webhook_events';

        require_once ABSPATH . 'wp-admin/includes/upgrade.php';

        dbDelta("CREATE TABLE $ev (
            id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            event_id VARCHAR(128) NOT NULL UNIQUE,
            event_type VARCHAR(64) NOT NULL,
            resource_id VARCHAR(64) NULL,
            correlation_id VARCHAR(128) NULL,
            payload LONGTEXT NOT NULL,
            processed_at DATETIME NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            INDEX (event_type),
            INDEX (resource_id)
        ) $charset;");
    }
}
```

> Dados da transação ficam em **meta do pedido WC** (`_pagou_transaction_id`, `_pagou_pix_qr_code`, `_pagou_pix_code`, `_pagou_raw`). Não duplicar tabela.

## 4. Gateway

`includes/class-wc-pagou-gateway.php`:

```php
<?php
if (! defined('ABSPATH')) exit;

class WC_Pagou_Pix_Gateway extends WC_Payment_Gateway
{
    public function __construct()
    {
        $this->id = 'pagou_pix';
        $this->method_title = 'Pagou PIX';
        $this->method_description = 'PIX via Pagou.ai';
        $this->has_fields = false;
        $this->supports = ['products'];

        $this->init_form_fields();
        $this->init_settings();

        $this->title = $this->get_option('title', 'PIX');
        $this->description = $this->get_option('description', 'Pagamento instantâneo via PIX');
        $this->enabled = $this->get_option('enabled');

        add_action('woocommerce_update_options_payment_gateways_' . $this->id, [$this, 'process_admin_options']);
        add_action('woocommerce_thankyou_' . $this->id, [$this, 'thankyou_page']);
    }

    public function init_form_fields(): void
    {
        $this->form_fields = [
            'enabled' => ['title' => 'Ativar', 'type' => 'checkbox', 'default' => 'no'],
            'title' => ['title' => 'Título no checkout', 'type' => 'text', 'default' => 'PIX'],
            'description' => ['title' => 'Descrição', 'type' => 'textarea', 'default' => 'Pagamento instantâneo via PIX'],
            'api_key' => ['title' => 'API Key', 'type' => 'password'],
            'env' => ['title' => 'Ambiente', 'type' => 'select', 'options' => ['sandbox' => 'Sandbox', 'production' => 'Produção'], 'default' => 'sandbox'],
        ];
    }

    public function process_payment($order_id): array
    {
        $order = wc_get_order($order_id);
        if (! $order) return ['result' => 'fail'];

        $amount_cents = (int) round(((float) $order->get_total()) * 100);

        $resp = Pagou_Pix_WC_Client::request('POST', '/v2/transactions', [
            'external_ref' => (string) $order_id,
            'amount' => $amount_cents,
            'currency' => 'BRL',
            'method' => 'pix',
            'buyer' => [
                'name' => trim($order->get_billing_first_name() . ' ' . $order->get_billing_last_name()),
                'email' => $order->get_billing_email(),
                'document' => [
                    'type' => 'CPF',
                    'number' => preg_replace('/\D/', '', (string) $order->get_meta('_billing_cpf')),
                ],
            ],
        ], $this->get_option('api_key'), $this->get_option('env'));

        if (! empty($resp['error']) || empty($resp['id'])) {
            wc_add_notice('Falha ao gerar PIX. Tente novamente.', 'error');
            return ['result' => 'fail'];
        }

        $order->update_meta_data('_pagou_transaction_id', $resp['id']);
        $order->update_meta_data('_pagou_pix_qr_code', $resp['pix_qr_code'] ?? '');
        $order->update_meta_data('_pagou_pix_code', $resp['pix_code'] ?? '');
        $order->update_meta_data('_pagou_raw', wp_json_encode($resp));
        $order->update_status('on-hold', 'Aguardando confirmação do PIX (Pagou).');
        $order->save();

        return ['result' => 'success', 'redirect' => $this->get_return_url($order)];
    }

    public function thankyou_page($order_id): void
    {
        $order = wc_get_order($order_id);
        if (! $order) return;
        $qr = $order->get_meta('_pagou_pix_qr_code');
        $code = $order->get_meta('_pagou_pix_code');
        if (! $qr && ! $code) return;
        ?>
        <h2>Pague com PIX</h2>
        <?php if ($qr): ?>
            <img src="data:image/png;base64,<?php echo esc_attr($qr); ?>" alt="PIX QR Code" style="max-width:280px;">
        <?php endif; ?>
        <?php if ($code): ?>
            <p><strong>PIX copia e cola</strong></p>
            <textarea readonly style="width:100%;height:80px;"><?php echo esc_textarea($code); ?></textarea>
        <?php endif; ?>
        <p>Após o pagamento, atualizaremos seu pedido automaticamente.</p>
        <?php
    }
}
```

## 5. Cliente

`includes/class-pagou-client.php`:

```php
<?php
if (! defined('ABSPATH')) exit;

class Pagou_Pix_WC_Client
{
    const BASE = [
        'sandbox' => 'https://api-sandbox.pagou.ai',
        'production' => 'https://api.pagou.ai',
    ];

    public static function request(string $method, string $path, ?array $body = null, ?string $key = null, ?string $env = 'sandbox'): array
    {
        if (empty($key)) return ['error' => 'missing_api_key'];

        $args = [
            'method' => $method,
            'timeout' => 15,
            'headers' => [
                'Authorization' => 'Bearer ' . $key,
                'Content-Type' => 'application/json',
                'Accept' => 'application/json',
            ],
        ];
        if ($body !== null) $args['body'] = wp_json_encode($body);

        $resp = wp_remote_request(self::BASE[$env] . $path, $args);
        if (is_wp_error($resp)) return ['error' => $resp->get_error_message()];

        $code = wp_remote_retrieve_response_code($resp);
        $data = json_decode(wp_remote_retrieve_body($resp), true) ?: [];

        if ($code >= 400) return ['error' => "pagou_{$code}", 'body' => $data];
        return $data;
    }
}
```

## 6. Status map

`includes/class-status-map.php`:

```php
<?php
if (! defined('ABSPATH')) exit;

class Pagou_Pix_WC_Status_Map
{
    // Pagou status → WC status (sem prefixo "wc-")
    const MAP = [
        'pending' => 'on-hold',
        'paid' => 'processing',           // ou 'completed' se o produto for digital
        'expired' => 'cancelled',
        'canceled' => 'cancelled',
        'refused' => 'failed',
        'refunded' => 'refunded',
        'partially_refunded' => 'refunded',
        'chargedback' => 'failed',
    ];

    public static function to_wc(string $pagou): string
    {
        return self::MAP[$pagou] ?? 'on-hold';
    }
}
```

## 7. Webhook

`includes/class-webhook.php`:

```php
<?php
if (! defined('ABSPATH')) exit;

class Pagou_Pix_WC_Webhook
{
    public static function register_routes(): void
    {
        register_rest_route('pagou/v1', '/webhook', [
            'methods' => 'POST',
            'callback' => [__CLASS__, 'handle'],
            'permission_callback' => '__return_true',
        ]);
    }

    public static function handle(WP_REST_Request $req): WP_REST_Response
    {
        $payload = $req->get_json_params();
        if (! is_array($payload) || ($payload['event'] ?? null) !== 'transaction' || empty($payload['id'])) {
            return new WP_REST_Response(['received' => true], 200);
        }

        global $wpdb;
        $ev_table = $wpdb->prefix . 'pagou_webhook_events';

        $ok = $wpdb->insert($ev_table, [
            'event_id' => $payload['id'],
            'event_type' => $payload['data']['event_type'] ?? 'unknown',
            'resource_id' => $payload['data']['id'] ?? null,
            'correlation_id' => $payload['data']['correlation_id'] ?? null,
            'payload' => wp_json_encode($payload),
        ]);

        if ($ok === false) return new WP_REST_Response(['received' => true], 200);

        wp_schedule_single_event(time() + 1, 'pagou_pix_wc_process_event', [$payload['id']]);

        return new WP_REST_Response(['received' => true], 200);
    }
}

add_action('pagou_pix_wc_process_event', function (string $event_id) {
    global $wpdb;
    $ev_table = $wpdb->prefix . 'pagou_webhook_events';
    $row = $wpdb->get_row($wpdb->prepare("SELECT * FROM $ev_table WHERE event_id = %s", $event_id), ARRAY_A);
    if (! $row || $row['processed_at']) return;

    $payload = json_decode($row['payload'], true) ?: [];
    $data = $payload['data'] ?? [];
    $order_id = $data['correlation_id'] ?? null;
    if (! $order_id) return;

    $order = wc_get_order((int) $order_id);
    if (! $order) return;

    $event_type = $data['event_type'] ?? '';
    $pagou_status = $data['status'] ?? '';
    $wc_status = Pagou_Pix_WC_Status_Map::to_wc($pagou_status);

    if ($event_type === 'transaction.paid') {
        $order->payment_complete($data['id'] ?? null);
        $order->add_order_note('PIX confirmado via webhook Pagou (event_id ' . $event_id . ')');
    } else {
        $order->update_status($wc_status, 'Pagou: ' . $pagou_status . ' (event_id ' . $event_id . ')');
    }

    $wpdb->update($ev_table, ['processed_at' => current_time('mysql')], ['event_id' => $event_id]);
});
```

## 8. Testes

```php
class Test_Pagou_WC_Webhook extends WP_UnitTestCase {
    public function test_marks_order_paid_on_transaction_paid() {
        $order = wc_create_order();
        $order->set_total('15.00');
        $order->set_status('on-hold');
        $order->save();

        $req = new WP_REST_Request('POST', '/pagou/v1/webhook');
        $req->set_body(wp_json_encode([
            'id' => 'evt_pay_x1',
            'event' => 'transaction',
            'data' => [
                'event_type' => 'transaction.paid',
                'id' => 'tr_x1',
                'status' => 'paid',
                'correlation_id' => (string) $order->get_id(),
            ],
        ]));
        $req->set_header('Content-Type', 'application/json');

        Pagou_Pix_WC_Webhook::handle($req);
        do_action('pagou_pix_wc_process_event', 'evt_pay_x1');

        $order = wc_get_order($order->get_id());
        $this->assertSame('processing', $order->get_status());
    }
}
```

## 9. Verificação

- Ativar gateway em **WooCommerce → Configurações → Pagamentos**
- Preencher API key e ambiente
- Fazer um pedido de teste em sandbox
- Disparar webhook sandbox (modo `webhook`) ou esperar 1–2 min pelo poller (modo `polling`) e confirmar mudança de status do pedido

---

## 10. Modo polling-only (v2.0.0+)

Aplicar **apenas se** o utilizador respondeu `polling` à 5ª pergunta.

### wp-cron + system cron

Reutilizar o padrão do `frameworks/wordpress.md` secção 11 (intervalos `pagou_one_minute` e `pagou_fifteen_minutes`), com a diferença que a propagação de status passa pelo método nativo do WooCommerce:

```php
add_action('pagou_pix_poll', function () {
    // ... query igual ao WP plain ...

    foreach ($rows as $tx) {
        $remote = pagou_api_get("/v2/transactions/{$tx->pagou_transaction_id}");
        if ($remote['status'] === $tx->status) continue;

        // Atualizar transação Pagou
        $wpdb->update($table_tx,
            ['status' => $remote['status'], 'updated_at' => current_time('mysql')],
            ['id' => $tx->id]
        );

        // Propagar para o WC Order (HPOS-safe)
        $order = wc_get_order($tx->external_ref);
        if (!$order) continue;

        switch ($remote['status']) {
            case 'paid':
                $order->payment_complete($tx->pagou_transaction_id);
                break;
            case 'expired':
            case 'canceled':
            case 'refused':
                $order->update_status('cancelled', 'PIX ' . $remote['status']);
                break;
        }
        $order->save();
    }
});
```

### Reconciliação tardia para refund/chargeback

`add_action('pagou_pix_reconcile_late', ...)` igual ao do WP plain mas com `$order->update_status('refunded', ...)` ou `'on-hold'` para chargeback (a definir conforme política da loja).

### Notas

- Em modo polling, **não** registar webhook URL no painel da Pagou. O endpoint REST continua a ser servido pelo plugin.
- Configurar **system cron real** a chamar `wp-cron.php` é especialmente crítico em lojas WooCommerce com tráfego variável.
- Se a loja já usa **Action Scheduler** (vem com WooCommerce), preferir `as_schedule_recurring_action()` em vez de `wp_schedule_event()` — é mais robusto para volume alto:

  ```php
  as_schedule_recurring_action(time(), 60, 'pagou_pix_poll');
  as_schedule_recurring_action(time(), 900, 'pagou_pix_reconcile_late');
  ```
