# Prompt — Architecture Discovery (Fase 1.b)

**Objetivo:** descobrir como o projeto está organizado para encaixar a integração PIX de forma idiomática.

## Padrões a identificar

### Padrão arquitetural

| Pista | Padrão |
|---|---|
| Pastas `controllers/`, `services/`, `repositories/` | MVC em camadas / Repository |
| Pastas `domain/`, `application/`, `infrastructure/` | Hexagonal / Clean |
| Pastas `modules/<x>/` com `controller.ts` + `service.ts` por módulo | Modular (NestJS, Laravel modules, Django apps) |
| `app/api/<x>/route.ts` | Next.js App Router file-based |
| `pages/api/<x>.ts` | Next.js Pages Router file-based |
| `urls.py` + `views.py` | Django |
| `config/routes.rb` + `app/controllers/` | Rails |
| Apenas funções soltas em arquivos | Script-style / serverless functions |

### Estilo de error handling

- `try/catch` por handler
- Middleware central de erro (Express `app.use((err, req, res, next))`, Laravel `Handler`, NestJS `ExceptionFilter`)
- Result/Either (TS funcional, F#, Rust)

A integração deve **seguir o estilo existente**, não introduzir novo.

### Estilo de logging

- `console.log` cru → não usar; só se nada melhor existir
- `pino`, `winston`, `bunyan` → reusar
- `Log::info()` Laravel → reusar
- `logger.info()` Python/Django → reusar
- `Rails.logger` → reusar

**Sempre mascarar `Authorization` header e qualquer string que contenha `api_key` ou `pgct_` antes de logar.**

### Convenção de nomes de tabelas

| Convenção | Decisão para tabelas Pagou |
|---|---|
| snake_case plural (`orders`) | `pagou_pix_transactions`, `pagou_webhook_events` |
| camelCase singular (`Order`) | `PagouPixTransaction`, `PagouWebhookEvent` |
| PascalCase (.NET) | `PagouPixTransactions`, `PagouWebhookEvents` |

Seguir o que o projeto já usa.

### Convenção de IDs

| Convenção | Usar para tabelas Pagou |
|---|---|
| `BIGSERIAL` / auto-increment | mesmo |
| `uuid` (Postgres) | mesmo |
| `cuid()` (Prisma) | mesmo |
| `ULID` | mesmo |

### Fluxo de checkout existente

Mapear ponta a ponta:

1. Onde o usuário inicia um pedido
2. Onde o pedido é persistido
3. Como o método de pagamento é escolhido
4. Onde a chamada ao gateway acontece
5. Como o estado final é confirmado
6. Como o frontend é notificado

A integração PIX deve **encaixar como um método de pagamento adicional** no mesmo fluxo. Não criar fluxo paralelo.

### Pasta-alvo para o código da integração

| Framework | Pasta sugerida |
|---|---|
| Next.js | `src/lib/pagou/`, `app/api/pagou/`, `app/api/webhooks/pagou/` |
| Laravel | `app/Services/Pagou/`, `app/Http/Controllers/PagouPixController.php`, `app/Jobs/ProcessPagouEvent.php` |
| WordPress puro | `wp-content/plugins/pagou-pix/` |
| WooCommerce | `wp-content/plugins/pagou-pix-wc/` |
| Django | `pagou/` app + `pagou/urls.py`, `pagou/services.py`, `pagou/views.py` |
| FastAPI | `app/integrations/pagou/` |
| Rails | `app/services/pagou/`, `app/controllers/pagou_pix_controller.rb` |
| Express | `src/integrations/pagou/` + `src/routes/pagou.ts` |
| Go | `internal/pagou/` |
| .NET | `Services/Pagou/`, `Controllers/PagouPixController.cs` |

## Saída da fase

Acrescentar ao bloco YAML mental:

```yaml
arch_pattern: <ex.: layered MVC + services>
error_style: <ex.: middleware central>
logger: <ex.: pino>
db_naming: <ex.: snake_case plural>
id_strategy: <ex.: uuid>
existing_checkout_path: <ex.: app/(shop)/checkout/page.tsx>
order_persistence_step: <ex.: services/orders/create.ts → prisma.order.create>
payment_init_step: <ex.: ainda não existe>
pix_code_target_folder: src/lib/pagou
webhook_target_route: /api/webhooks/pagou
public_endpoint: /api/pagou/pix
```

## Regras

- Encaixar no que existe — **nunca** reorganizar o projeto para acomodar a Skill
- Se o projeto já tem outro gateway (Stripe, MP, PagSeguro), a Skill **não toca** nele — só adiciona PIX como método paralelo
- Se padrão arquitetural for ambíguo, preferir o mais simples que **se pareça com o resto do código**
