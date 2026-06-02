# Prompt — PIX Integration (Fase 3.a)

**Objetivo:** implementar criação de cobrança PIX seguindo o adapter do framework.

## Pré-requisitos

- Fases 1 e 2 concluídas
- Aprovação explícita do plano obtida
- Adapter de framework selecionado (`frameworks/<x>.md`)

## Ordem de implementação

1. **`.env.example`** — adicionar `PAGOU_API_KEY`, `PAGOU_ENV`, `PAGOU_BASE_URL` (opcional), `PUBLIC_APP_URL`
2. **Migração** — criar `pagou_pix_transactions` e `pagou_webhook_events` conforme adapter
3. **Cliente Pagou** — wrapper HTTP com auth, base URL por ambiente, error class própria
4. **Status mapping** — função `mapStatus(pagou_status) → internal_status`
5. **Serviço PIX** — `createPixCharge(order)` e `getTransaction(id)`
6. **Endpoint público** — receber `order_id`, chamar serviço, persistir, retornar QR + copia-e-cola
7. **Frontend hint** — atualizar `README_PAGOU_PIX.md` com snippet de consumo

## Contrato da chamada à Pagou

```http
POST {base_url}/v2/transactions
Authorization: Bearer {PAGOU_API_KEY}
Content-Type: application/json

{
  "external_ref": "<id interno do pedido>",
  "amount":       <valor em centavos>,
  "currency":     "BRL",
  "method":       "pix",
  "buyer": {
    "name":  "<nome do pagador>",
    "email": "<email>",
    "document": { "type": "CPF" | "CNPJ", "number": "<somente dígitos>" }
  }
}
```

### Campos obrigatórios na **requisição**

- `external_ref` — id interno (idempotência + reconciliação)
- `amount` — inteiro, em centavos (ex.: R$15,00 = 1500)
- `currency` — sempre `"BRL"` para PIX
- `method` — sempre `"pix"`
- `buyer.name`, `buyer.email`, `buyer.document.type`, `buyer.document.number`

### Campos esperados na **resposta**

- `id` — id da transação Pagou (`tr_...`)
- `status` — geralmente `"pending"` na criação
- `pix_qr_code` — string base64 (renderizar como imagem)
- `pix_code` — string copia-e-cola (BR Code/EMV)

## Persistência

Após criar com sucesso na Pagou, **upsert** em `pagou_pix_transactions`:

- Chave de upsert: `external_ref` (não `pagou_transaction_id` — porque pode ser re-tentativa antes de obter resposta)
- Salvar `raw_response` cru — auditoria
- Status inicial = o que a Pagou retornou (geralmente `pending`)

**Não** mover o pedido para "pago" — isso é exclusivo do webhook.

## Idempotência da criação

Se o endpoint público for chamado duas vezes para o mesmo `orderId`:

- Procurar `pagou_pix_transactions` por `external_ref = orderId`
- Se existe e status é `pending`, devolver os dados existentes (mesmo QR/code) — não criar nova cobrança
- Se existe e está em estado terminal (`paid`, `expired`, etc.), retornar erro de domínio ("Pedido já finalizado")

Isso evita duplicar cobranças quando o frontend é instável.

## Tratamento de erros

| Erro Pagou | Ação |
|---|---|
| HTTP 401 | Logar `PAGOU_API_KEY inválida` (sem ecoar a chave), retornar 500 ao client |
| HTTP 4xx outros | Retornar 400 ao client com `error.code` mapeado |
| HTTP 5xx ou network | Retornar 502 ao client + agendar retry curto (1 tentativa, 1s) |
| Timeout | Retornar 504 + registrar warning |

Em todos os casos:

- Logar `requestId` (se vier no header `x-request-id`)
- Logar `external_ref`
- **Nunca** logar o header `Authorization` nem a `api_key`

## Logs estruturados

Cada chamada deve produzir:

```json
{
  "event": "pagou.pix.create",
  "external_ref": "order_1001",
  "transaction_id": "tr_1001",
  "status": "pending",
  "request_id": "req_abc",
  "elapsed_ms": 380
}
```

Use o logger do projeto (pino, winston, monolog, Log facade, structlog, etc.). Nunca `console.log` cru se houver alternativa.

## Validações antes de chamar a Pagou

1. `amount_cents > 0`
2. `currency === "BRL"`
3. `buyer.document.number` apenas dígitos, comprimento válido (11 para CPF, 14 para CNPJ)
4. `buyer.email` formato mínimo válido
5. `external_ref` não vazio, ≤ 128 chars

Se falhar, retornar 400 ao client com o motivo — **não** chamar a Pagou.

## Saída desta fase

- Arquivos criados/modificados conforme plano aprovado
- Endpoint testado manualmente com `curl` ou Insomnia/Postman → status 200 e `pix_qr_code` válido em sandbox
- Próxima fase: `webhook-integration.md`
