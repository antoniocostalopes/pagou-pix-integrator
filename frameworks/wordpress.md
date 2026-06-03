# Adapter — WordPress (sem WooCommerce)

## Detecção

| Sinal | Verificar |
|---|---|
| `wp-config.php` na raiz | obrigatório |
| `wp-content/plugins/` | onde criar o plugin |
| `wp-includes/version.php` | versão do WP (>= 6.0) |
| `wp-content/plugins/woocommerce/woocommerce.php` ausente | usar este adapter; se presente → `woocommerce.md` |

A integração é entregue como um **plugin** próprio para isolar bem o código. Nunca editar core nem `wp-config.php`.

---

## 1. Estrutura do plugin

```
wp-content/plugins/pagou-pix/
├── pagou-pix.php           ← bootstrap do plugin
├── includes/
│   ├── class-pagou-client.php
│   ├── class-pix-service.php
│   ├── class-webhook.php
│   ├── class-status-map.php
│   └── class-installer.php
├── readme.txt
└── uninstall.php
```

## 2. Bootstrap

`wp-content/plugins/pagou-pix/pagou-pix.php`:

```php
<?php
/**
 * Plugin Name: Pagou PIX
 * Description: Integração PIX via Pagou.ai
 * Version: 1.0.0
 * Requires at least: 6.0
 * Requires PHP: 8.0
 */

if (! defined('ABSPATH')) exit;

define('PAGOU_PIX_DIR', plugin_dir_path(__FILE__));
define('PAGOU_PIX_URL', plugin_dir_url(__FILE__));

require_once PAGOU_PIX_DIR . 'includes/class-installer.php';
require_once PAGOU_PIX_DIR . 'includes/class-status-map.php';
require_once PAGOU_PIX_DIR . 'includes/class-pagou-client.php';
require_once PAGOU_PIX_DIR . 'includes/class-pix-service.php';
require_once PAGOU_PIX_DIR . 'includes/class-webhook.php';

register_activation_hook(__FILE__, ['Pagou_Pix_Installer', 'install']);

add_action('init', function () {
    Pagou_Pix_Webhook::register_routes();
});

add_action('admin_menu', function () {
    add_options_page('Pagou PIX', 'Pagou PIX', 'manage_options', 'pagou-pix', 'pagou_pix_settings_page');
});

function pagou_pix_settings_page() {
    if (! current_user_can('manage_options')) return;
    if (isset($_POST['pagou_pix_save']) && check_admin_referer('pagou_pix_save')) {
        update_option('pagou_pix_api_key', sanitize_text_field($_POST['api_key'] ?? ''), false);
        echo '<div class="updated"><p>Salvo.</p></div>';
    }
    $key = get_option('pagou_pix_api_key', '');
    ?>
    <div class="wrap">
        <h1>Pagou PIX</h1>
        <form method="post">
            <?php wp_nonce_field('pagou_pix_save'); ?>
            <table class="form-table">
                <tr><th>API Key (PRODUÇÃO)</th><td><input type="password" name="api_key" value="<?php echo esc_attr($key); ?>" class="regular-text"><p class="description">A Skill chama sempre <code>https://api.pagou.ai</code>. Para dev local, usar <code>tools/pagou-mock/</code>.</p></td></tr>
                <tr><th>Webhook URL</th><td><code><?php echo esc_url(rest_url('pagou/v1/webhook')); ?></code></td></tr>
            </table>
            <?php submit_button('Salvar', 'primary', 'pagou_pix_save'); ?>
        </form>
    </div>
    <?php
}
```

## 3. Installer (cria tabelas)

`includes/class-installer.php`:

```php
<?php
if (! defined('ABSPATH')) exit;

class Pagou_Pix_Installer
{
    public static function install(): void
    {
        global $wpdb;
        $charset = $wpdb->get_charset_collate();

        $tx = $wpdb->prefix . 'pagou_pix_transactions';
        $ev = $wpdb->prefix . 'pagou_webhook_events';

        require_once ABSPATH . 'wp-admin/includes/upgrade.php';

        dbDelta("CREATE TABLE $tx (
            id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            pagou_transaction_id VARCHAR(64) NOT NULL UNIQUE,
            external_ref VARCHAR(128) NOT NULL UNIQUE,
            post_id BIGINT UNSIGNED NULL,
            user_id BIGINT UNSIGNED NULL,
            amount_cents INT UNSIGNED NOT NULL,
            currency CHAR(3) DEFAULT 'BRL',
            status VARCHAR(32) NOT NULL,
            pix_qr_code LONGTEXT NULL,
            pix_code LONGTEXT NULL,
            raw_response LONGTEXT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX (status),
            INDEX (post_id)
        ) $charset;");

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

## 4. Status map

`includes/class-status-map.php`:

```php
<?php
if (! defined('ABSPATH')) exit;

class Pagou_Pix_Status_Map
{
    const MAP = [
        'pending' => 'aguardando_pagamento',
        'paid' => 'pago',
        'expired' => 'expirado',
        'canceled' => 'cancelado',
        'refused' => 'recusado',
        'refunded' => 'estornado',
        'partially_refunded' => 'estornado_parcial',
        'chargedback' => 'chargeback',
    ];

    public static function to_internal(string $pagou): string
    {
        return self::MAP[$pagou] ?? 'desconhecido';
    }
}
```

## 5. Cliente

`includes/class-pagou-client.php`:

```php
<?php
if (! defined('ABSPATH')) exit;

class Pagou_Pix_Client
{
    // v3.0.0+ — apenas produção
    const BASE = 'https://api.pagou.ai';

    public static function request(string $method, string $path, array $body = null): array
    {
        $key = get_option('pagou_pix_api_key');
        if (empty($key)) {
            return ['error' => 'PAGOU_API_KEY missing'];
        }

        $args = [
            'method' => $method,
            'timeout' => 15,
            'headers' => [
                'Authorization' => 'Bearer ' . $key,
                'Content-Type' => 'application/json',
                'Accept' => 'application/json',
            ],
        ];

        if ($body !== null) {
            $args['body'] = wp_json_encode($body);
        }

        $resp = wp_remote_request(self::BASE . $path, $args);

        if (is_wp_error($resp)) {
            return ['error' => $resp->get_error_message()];
        }

        $code = wp_remote_retrieve_response_code($resp);
        $data = json_decode(wp_remote_retrieve_body($resp), true) ?: [];

        if ($code >= 400) {
            return ['error' => "Pagou {$code}", 'body' => $data];
        }

        return $data;
    }
}
```

## 6. Serviço PIX

`includes/class-pix-service.php`:

```php
<?php
if (! defined('ABSPATH')) exit;

class Pagou_Pix_Service
{
    public static function create_charge(array $args): array
    {
        global $wpdb;

        $resp = Pagou_Pix_Client::request('POST', '/v2/transactions', [
            'external_ref' => $args['external_ref'],
            'amount' => (int) $args['amount_cents'],
            'currency' => 'BRL',
            'method' => 'pix',
            'buyer' => $args['buyer'],
        ]);

        if (isset($resp['error'])) return $resp;

        $table = $wpdb->prefix . 'pagou_pix_transactions';

        $wpdb->replace($table, [
            'pagou_transaction_id' => $resp['id'],
            'external_ref' => $args['external_ref'],
            'post_id' => $args['post_id'] ?? null,
            'user_id' => $args['user_id'] ?? null,
            'amount_cents' => (int) $args['amount_cents'],
            'currency' => 'BRL',
            'status' => $resp['status'],
            'pix_qr_code' => $resp['pix_qr_code'] ?? null,
            'pix_code' => $resp['pix_code'] ?? null,
            'raw_response' => wp_json_encode($resp),
        ]);

        return $resp;
    }
}
```

## 7. Webhook (REST API)

`includes/class-webhook.php`:

```php
<?php
if (! defined('ABSPATH')) exit;

class Pagou_Pix_Webhook
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
        $table = $wpdb->prefix . 'pagou_webhook_events';

        $inserted = $wpdb->insert($table, [
            'event_id' => $payload['id'],
            'event_type' => $payload['data']['event_type'] ?? 'unknown',
            'resource_id' => $payload['data']['id'] ?? null,
            'correlation_id' => $payload['data']['correlation_id'] ?? null,
            'payload' => wp_json_encode($payload),
        ]);

        if ($inserted === false) {
            return new WP_REST_Response(['received' => true], 200);
        }

        wp_schedule_single_event(time() + 1, 'pagou_pix_process_event', [$payload['id']]);

        return new WP_REST_Response(['received' => true], 200);
    }
}

add_action('pagou_pix_process_event', function (string $event_id) {
    global $wpdb;
    $ev_table = $wpdb->prefix . 'pagou_webhook_events';
    $tx_table = $wpdb->prefix . 'pagou_pix_transactions';

    $row = $wpdb->get_row($wpdb->prepare("SELECT * FROM $ev_table WHERE event_id = %s", $event_id), ARRAY_A);
    if (! $row || $row['processed_at']) return;

    $payload = json_decode($row['payload'], true) ?: [];
    $data = $payload['data'] ?? [];

    if (! empty($data['id']) && ! empty($data['status'])) {
        $wpdb->update($tx_table, ['status' => $data['status']], ['pagou_transaction_id' => $data['id']]);
    }

    if (($data['event_type'] ?? '') === 'transaction.paid' && ! empty($data['correlation_id'])) {
        do_action('pagou_pix_paid', $data['correlation_id'], $data);
    }

    $wpdb->update($ev_table, ['processed_at' => current_time('mysql')], ['event_id' => $event_id]);
});
```

> O hook `do_action('pagou_pix_paid', ...)` permite que outros plugins/temas reajam (entregar conteúdo, enviar e-mail, etc.).

## 8. Uninstall

`uninstall.php`:

```php
<?php
if (! defined('WP_UNINSTALL_PLUGIN')) exit;

delete_option('pagou_pix_api_key');
delete_option('pagou_pix_env');
```

> Tabelas não são apagadas por padrão — manter histórico transacional. Documentar no README.

## 9. Testes (PHPUnit via wp-env)

`tests/test-webhook.php`:

```php
<?php
class Test_Pagou_Webhook extends WP_UnitTestCase {
    public function test_dedupes_by_event_id() {
        $req = new WP_REST_Request('POST', '/pagou/v1/webhook');
        $req->set_body(wp_json_encode([
            'id' => 'evt_pay_1001',
            'event' => 'transaction',
            'data' => ['event_type' => 'transaction.paid', 'id' => 'tr_1', 'status' => 'paid'],
        ]));
        $req->set_header('Content-Type', 'application/json');

        Pagou_Pix_Webhook::handle($req);
        Pagou_Pix_Webhook::handle($req);

        global $wpdb;
        $count = (int) $wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->prefix}pagou_webhook_events WHERE event_id='evt_pay_1001'");
        $this->assertSame(1, $count);
    }
}
```

## 10. Verificação

- Ativar plugin no admin
- Configurar API key e ambiente
- Registrar webhook URL na Pagou (só se modo = `webhook`)
- Disparar evento simulado via `tools/webhook-tester/` (HMAC válido, sem tocar em produção) e verificar `wp_pagou_webhook_events`

---

## 11. Modo polling-only (v2.0.0+)

Aplicar **apenas se** o utilizador respondeu `polling` à 5ª pergunta.

### Background poller via wp-cron

No activate do plugin:

```php
register_activation_hook(__FILE__, function () {
    if (get_option('pagou_confirmation_mode') === 'polling') {
        if (!wp_next_scheduled('pagou_pix_poll')) {
            wp_schedule_event(time(), 'pagou_one_minute', 'pagou_pix_poll');
        }
        if (!wp_next_scheduled('pagou_pix_reconcile_late')) {
            wp_schedule_event(time(), 'pagou_fifteen_minutes', 'pagou_pix_reconcile_late');
        }
    }
});

// Adicionar intervalos custom (wp-cron não os tem por defeito)
add_filter('cron_schedules', function ($schedules) {
    $schedules['pagou_one_minute']     = ['interval' => 60,   'display' => 'Pagou — every minute'];
    $schedules['pagou_fifteen_minutes']= ['interval' => 900,  'display' => 'Pagou — every 15 minutes'];
    return $schedules;
});
```

### Handlers dos hooks

```php
add_action('pagou_pix_poll', function () {
    global $wpdb;
    $table = $wpdb->prefix . 'pagou_pix_transactions';
    $rows = $wpdb->get_results(
        "SELECT * FROM {$table}
         WHERE status IN ('pending','created')
         AND created_at >= DATE_SUB(NOW(), INTERVAL 1 HOUR)
         LIMIT 100"
    );

    foreach ($rows as $tx) {
        try {
            $remote = pagou_api_get("/v2/transactions/{$tx->pagou_transaction_id}");
            if ($remote['status'] === $tx->status) continue;

            $wpdb->update($table,
                ['status' => $remote['status'], 'updated_at' => current_time('mysql')],
                ['id' => $tx->id]
            );

            if (in_array($remote['status'], ['paid','expired','canceled','refused'])) {
                pagou_propagate_to_order($tx->external_ref, $remote['status']);
            }
        } catch (\Throwable $e) {
            error_log('pagou.poll.error ' . $e->getMessage());
        }
    }
});

add_action('pagou_pix_reconcile_late', function () {
    // Mesmo padrão, mas filtrar por status IN ('paid','expired','canceled')
    // e propagar refunded/partially_refunded/chargedback.
});
```

### Limitações específicas do WordPress

- **wp-cron depende de tráfego ao site** para disparar — em sites com pouco tráfego, configurar **system cron real** apontando para `wp-cron.php`:

  ```cron
  * * * * * curl -s https://seusite.com/wp-cron.php?doing_wp_cron > /dev/null
  ```

- Sem isto, a janela de 1 minuto não é confiável e pode disparar 5–10 min depois.
- Em modo polling, a opção `pagou_confirmation_mode` é guardada em `wp_options` (registar via Settings API).
