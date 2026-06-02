# Prompt — Project Discovery (Fase 1.a)

**Objetivo:** identificar stack, framework, linguagem e padrão geral do projeto **sem fazer perguntas** ao usuário.

## Ordem de leitura

Tente nesta ordem; pare assim que tiver dados conclusivos.

### 1. Manifestos

| Arquivo | O que indica |
|---|---|
| `package.json` | Node/TS — verificar `dependencies` e `scripts` |
| `composer.json` | PHP — verificar `require` |
| `requirements.txt` / `pyproject.toml` / `Pipfile` | Python |
| `Gemfile` | Ruby |
| `go.mod` | Go |
| `*.csproj` / `*.sln` | .NET |
| `Cargo.toml` | Rust |
| `pom.xml` / `build.gradle*` | Java/Kotlin |
| `wp-config.php` | WordPress |

### 2. Markers de framework

| Marker | Framework |
|---|---|
| `"next"` em deps + `next.config.*` | **Next.js** |
| `"@nestjs/core"` | NestJS |
| `"express"` ou `"fastify"` | Express/Fastify |
| `"laravel/framework"` + `artisan` | **Laravel** |
| `"symfony/framework-bundle"` | Symfony |
| `wp-config.php` + ausência de WooCommerce plugin | **WordPress puro** |
| `wp-config.php` + plugin `woocommerce` ativo | **WooCommerce** |
| `Django==` ou `django` em deps | Django |
| `fastapi` em deps | FastAPI |
| `flask` em deps | Flask |
| `rails` em Gemfile | Rails |
| `gin-gonic`, `gofiber`, `go-chi` | Go web |
| `Microsoft.AspNetCore` | ASP.NET Core |

### 3. Arquivos chave a inspecionar (não modificar nesta fase)

- `README.md`, `README*.md`
- `.env.example` / `.env.sample`
- `Dockerfile`, `docker-compose.*`
- `tsconfig.json`, `vite.config.*`, `next.config.*`
- `database/migrations/`, `prisma/`, `db/`, `alembic/`, `migrations/`
- Pastas: `src/`, `app/`, `pages/`, `routes/`, `controllers/`, `services/`, `repositories/`, `models/`

### 4. Banco de dados / ORM

| Sinal | Tecnologia |
|---|---|
| `prisma/schema.prisma` | Prisma |
| `drizzle.config.*` | Drizzle |
| `ormconfig.*` ou imports de `typeorm` | TypeORM |
| `sequelize` em deps | Sequelize |
| `mongoose` em deps | Mongoose (Mongo) |
| `app/Models/` | Eloquent (Laravel) |
| `alembic/` | SQLAlchemy |
| `app/models/` em Rails | ActiveRecord |
| `gorm.io/gorm` | GORM |
| `EntityFrameworkCore` | EF Core |
| `DB_CONNECTION=mysql` em `.env` | MySQL/MariaDB |
| `DATABASE_URL=postgres://` | Postgres |
| `sqlite://` ou arquivo `.sqlite`/`.db` | SQLite |

### 5. Auth

| Sinal | Sistema |
|---|---|
| `next-auth` ou `@auth/...` | NextAuth |
| `laravel/sanctum`, `laravel/passport`, `laravel/breeze`, `laravel/jetstream` | Sanctum/Passport |
| `passport`, `passport-jwt` | PassportJS |
| `djangorestframework-simplejwt`, `django-allauth` | Django auth |
| `devise` em Gemfile | Devise |
| `jsonwebtoken` standalone | JWT custom |
| `wp_login.php` | WordPress nativo |

### 6. Fluxo de checkout existente

Grepar (case-insensitive):

```
checkout|pedido|order|cart|compra|payment|stripe|mercado.pago|pagseguro
```

em `routes/`, `controllers/`, `pages/`, `app/`, `src/`.

Identificar:

- Onde o pedido é criado
- Onde o pagamento é iniciado hoje (se já houver outro gateway)
- Qual o "estado de pagamento" do projeto (campo `status` ou similar)
- Como o frontend descobre o resultado do pagamento (polling, redirect, webhook próprio)

### 7. Convenções de teste

| Sinal | Framework de teste |
|---|---|
| `vitest` em deps | Vitest |
| `jest` em deps | Jest |
| `phpunit` em `composer.json` | PHPUnit |
| `pestphp/pest` | Pest |
| `pytest` em deps | Pytest |
| `rspec` em Gemfile | RSpec |
| `*_test.go` no projeto | testing |

## Saída da fase

Anotar mentalmente (para usar em fases seguintes):

```yaml
framework: <ex.: Next.js 14 App Router>
language: <ex.: TypeScript>
database: <ex.: Postgres>
orm: <ex.: Prisma>
auth: <ex.: NextAuth>
test_runner: <ex.: Vitest>
existing_payment_provider: <none | stripe | etc.>
order_model_location: <ex.: prisma model Order>
order_status_field: <ex.: Order.status>
public_url_hint: <ex.: lido de NEXT_PUBLIC_APP_URL ou perguntar>
```

## Regras

- Se algo for ambíguo (ex.: dois frameworks), preferir o de maior peso nos manifestos
- Se um campo não puder ser inferido, **não inventar** — registrar como "desconhecido" e tratar em `missing-data.md`
- Esta fase é silenciosa; única mensagem ao usuário é "Analisando o projeto…"
