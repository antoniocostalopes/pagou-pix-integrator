# TEST_REPORT

> Resultados dos testes executados após a implementação.

## Metadados

| Campo | Valor |
|---|---|
| Data | {{YYYY-MM-DD}} |
| Stack | {{framework + linguagem}} |
| Test runner | {{Vitest | Jest | PHPUnit | Pest | pytest | RSpec | go test | dotnet test}} |
| Ambiente | local |

## Comando de execução

```bash
{{npm test --coverage}}
```

## Resumo

| Tipo | Total | ✓ Passed | ✗ Failed | ⊘ Skipped |
|---|---|---|---|---|
| Unit | {{X}} | {{X}} | 0 | 0 |
| Integration | {{X}} | {{X}} | 0 | 0 |
| Webhook | {{X}} | {{X}} | 0 | 0 |
| E2E | {{X}} | {{X}} | 0 | 0 |
| **Total** | **{{X}}** | **{{X}}** | **0** | **0** |

Cobertura: {{XX}}% (linhas) / {{XX}}% (branches)

---

## Unit Tests

### Status mapping

| Caso | Esperado | Obtido | ✓/✗ |
|---|---|---|---|
| `mapStatus("pending")` | `aguardando_pagamento` | `aguardando_pagamento` | ✓ |
| `mapStatus("paid")` | `pago` | `pago` | ✓ |
| `mapStatus("expired")` | `expirado` | `expirado` | ✓ |
| `mapStatus("canceled")` | `cancelado` | `cancelado` | ✓ |
| `mapStatus("refused")` | `recusado` | `recusado` | ✓ |
| `mapStatus("refunded")` | `estornado` | `estornado` | ✓ |
| `mapStatus("partially_refunded")` | `estornado_parcial` | `estornado_parcial` | ✓ |
| `mapStatus("chargedback")` | `chargeback` | `chargeback` | ✓ |
| `mapStatus("alien")` | `desconhecido` | `desconhecido` | ✓ |

### Conversão de valores

| Entrada (BRL) | Saída (centavos) | ✓/✗ |
|---|---|---|
| R$ 15,00 | 1500 | ✓ |
| R$ 0,01 | 1 | ✓ |
| R$ 1234,56 | 123456 | ✓ |
| R$ 0 | 0 (rejeita: deve ser > 0) | ✓ |

### Validação de payload

- [x] Rejeita `amount <= 0`
- [x] Rejeita `currency != "BRL"`
- [x] Rejeita CPF com menos de 11 dígitos
- [x] Rejeita email malformado
- [x] Rejeita `external_ref` vazio

---

## Integration Tests

### Cliente Pagou (HTTP)

- [x] `pagouFetch` envia `Authorization: Bearer <key>`
- [x] `pagouFetch` envia `Content-Type: application/json`
- [x] Trata erro 401 (lança `PagouError` com status 401)
- [x] Trata erro 5xx
- [x] Timeout configurado

### Criar cobrança contra `tools/pagou-mock/` (dev) ou produção (smoke)

- [x] `POST /v2/transactions` retorna 200 com `pix_qr_code` não vazio
- [x] Retorna `pix_code` no formato esperado (string longa de BR Code)
- [x] Resposta persistida em `pagou_pix_transactions`
- [x] Upsert: segunda chamada com mesmo `external_ref` não cria nova linha

---

## Webhook Tests

### Dedup

- [x] POST com `event.id = "evt_test_1"` → 1 linha em `pagou_webhook_events`
- [x] POST repetido com mesmo `event.id` → ainda 1 linha (idempotente)
- [x] Resposta sempre `200 { received: true }`

### Validação

- [x] POST sem `id` top-level → 200 mas não persiste
- [x] POST com `event !== "transaction"` → 200 mas não persiste
- [x] POST com JSON inválido → 400

### Processamento

- [x] `transaction.paid` atualiza `pagou_pix_transactions.status` para `paid`
- [x] `transaction.paid` atualiza order (via `correlation_id`) para status interno `pago`
- [x] `transaction.cancelled` atualiza para `cancelled`
- [x] `transaction.refunded` atualiza para `refunded`
- [x] `processed_at` é setado após sucesso

### Performance

- [x] Handler responde em < 200ms (medido com timer)

---

## E2E Tests

### Fluxo feliz completo

```
1. Criar order de R$ 15,00 → status interno "novo"
2. POST /api/pagou/pix → recebe QR + status "pending"
3. Verificar pagou_pix_transactions tem 1 linha, status "pending"
4. Simular webhook transaction.paid
5. Aguardar job processar (<1s)
6. Verificar order.status = "pago"
7. Verificar pagou_webhook_events.processed_at não nulo
```

✓ Passou em {{X}}ms

### Fluxo com expiração

```
1. Criar cobrança
2. Simular webhook transaction.cancelled (por expiração)
3. Verificar order.status = "cancelado"
```

✓ Passou

### Fluxo com chargeback

```
1. Criar cobrança
2. Simular webhook transaction.paid
3. Simular webhook transaction.chargedback
4. Verificar order.status = "chargeback"
5. Verificar pagou_pix_transactions.status = "chargedback"
```

✓ Passou

### Idempotência de criação

```
1. POST /api/pagou/pix para mesmo order 2 vezes
2. Verificar 1 linha em pagou_pix_transactions
3. Verificar segunda resposta retorna mesmos QR/code da primeira
```

✓ Passou

---

## Falhas (se houver)

| Teste | Erro | Status |
|---|---|---|
| {{nome}} | {{mensagem}} | {{aberto / corrigido}} |

## Cobertura por arquivo

```
File                                | % Stmts | % Branch | % Lines |
------------------------------------|---------|----------|---------|
src/lib/pagou/client.ts             |   100   |    100   |   100   |
src/lib/pagou/pix.ts                |    95   |     88   |    95   |
src/lib/pagou/status.ts             |   100   |    100   |   100   |
app/api/pagou/pix/route.ts          |    92   |     85   |    92   |
app/api/webhooks/pagou/route.ts     |    96   |     90   |    96   |
------------------------------------|---------|----------|---------|
All files                           |    96   |     91   |    96   |
```

## Observações

- {{ex.: Teste de timeout não cobre cenário real de rede instável; documentado como melhoria futura}}
- {{ex.: E2E rodando contra DB em memória; em prod usar staging com Postgres real}}
