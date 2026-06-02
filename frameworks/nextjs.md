# Adapter — Next.js

## Detecção

| Sinal | Verificar |
|---|---|
| `package.json` contém `"next"` em dependencies | obrigatório |
| `next.config.js`, `next.config.ts` ou `next.config.mjs` | obrigatório |
| `app/` (App Router) ou `pages/` (Pages Router) | identifica roteamento |
| TypeScript: `tsconfig.json` presente | usar `.ts` em vez de `.js` |

## Variantes

- **App Router** (Next 13+) → rotas em `app/api/.../route.ts`
- **Pages Router** → rotas em `pages/api/...ts`

Detecte qual está em uso pela existência de `app/` ou `pages/`. Se ambos, prefira `app/`.

## ORM/DB esperados

- Prisma → `prisma/schema.prisma`
- Drizzle → `drizzle.config.*`
- Mongoose → `mongoose` em dependencies
- Outro/SQL cru → wrapper genérico

---

## 1. Variáveis de ambiente

`.env.local` (e `.env.example`):

```bash
PAGOU_API_KEY=                      # secret — backend only
PAGOU_WEBHOOK_SECRET=               # secret HMAC do webhook (do painel Pagou)
PAGOU_ENV=sandbox                   # sandbox | production
PAGOU_BASE_URL=                     # opcional; default por ambiente
PUBLIC_APP_URL=https://example.com  # usada para registrar webhook
```

## 2. Migration Prisma

`prisma/schema.prisma`:

```prisma
model PagouPixTransaction {
  id                  String   @id @default(cuid())
  pagouTransactionId  String   @unique
  externalRef         String   @unique
  orderId             String
  amountCents         Int
  currency            String   @default("BRL")
  status              String
  pixQrCode           String?  @db.Text
  pixCode             String?  @db.Text
  rawResponse         Json?
  createdAt           DateTime @default(now())
  updatedAt           DateTime @updatedAt

  @@index([orderId])
  @@index([status])
  @@map("pagou_pix_transactions")
}

model PagouWebhookEvent {
  id            String    @id @default(cuid())
  eventId       String    @unique
  eventType     String
  resourceId    String?
  correlationId String?
  payload       Json
  processedAt   DateTime?
  createdAt     DateTime  @default(now())

  @@index([eventType])
  @@index([resourceId])
  @@map("pagou_webhook_events")
}
```

Rodar:

```bash
npx prisma migrate dev --name add_pagou_pix
```

## 3. Cliente Pagou

`src/lib/pagou/client.ts`:

```ts
const BASE_URL_BY_ENV = {
  sandbox: "https://api-sandbox.pagou.ai",
  production: "https://api.pagou.ai",
} as const;

type PagouEnv = keyof typeof BASE_URL_BY_ENV;

function getEnv(): PagouEnv {
  const v = process.env.PAGOU_ENV;
  return v === "production" ? "production" : "sandbox";
}

function getBaseUrl(): string {
  return process.env.PAGOU_BASE_URL || BASE_URL_BY_ENV[getEnv()];
}

function getApiKey(): string {
  const key = process.env.PAGOU_API_KEY;
  if (!key) throw new Error("PAGOU_API_KEY is not set");
  return key;
}

export class PagouError extends Error {
  constructor(
    message: string,
    public status: number,
    public body: unknown,
  ) {
    super(message);
  }
}

export async function pagouFetch<T>(
  path: string,
  init: RequestInit = {},
): Promise<T> {
  const url = `${getBaseUrl()}${path}`;
  const res = await fetch(url, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${getApiKey()}`,
      ...(init.headers || {}),
    },
  });

  const text = await res.text();
  const body = text ? safeJson(text) : null;

  if (!res.ok) {
    throw new PagouError(
      `Pagou API error ${res.status} at ${path}`,
      res.status,
      body,
    );
  }

  return body as T;
}

function safeJson(s: string): unknown {
  try {
    return JSON.parse(s);
  } catch {
    return s;
  }
}
```

## 4. Serviço PIX

`src/lib/pagou/pix.ts`:

```ts
import { pagouFetch } from "./client";

export type PagouPixCreateInput = {
  externalRef: string;
  amountCents: number;
  buyer: {
    name: string;
    email: string;
    document: { type: "CPF" | "CNPJ"; number: string };
  };
};

export type PagouPixTransaction = {
  id: string;
  status: string;
  external_ref: string;
  pix_qr_code?: string;
  pix_code?: string;
  correlation_id?: string;
};

export async function createPixCharge(
  input: PagouPixCreateInput,
): Promise<PagouPixTransaction> {
  return pagouFetch<PagouPixTransaction>("/v2/transactions", {
    method: "POST",
    body: JSON.stringify({
      external_ref: input.externalRef,
      amount: input.amountCents,
      currency: "BRL",
      method: "pix",
      buyer: input.buyer,
    }),
  });
}

export async function getTransaction(id: string): Promise<PagouPixTransaction> {
  return pagouFetch<PagouPixTransaction>(`/v2/transactions/${id}`, {
    method: "GET",
  });
}

export async function cancelTransaction(id: string): Promise<PagouPixTransaction> {
  return pagouFetch<PagouPixTransaction>(`/v2/transactions/${id}/cancel`, {
    method: "POST",
  });
}

export async function refundTransaction(
  id: string,
  opts: { amountCents?: number; reason?: string } = {},
): Promise<PagouPixTransaction> {
  return pagouFetch<PagouPixTransaction>(`/v2/transactions/${id}/refund`, {
    method: "POST",
    body: JSON.stringify({
      ...(opts.amountCents !== undefined && { amount: opts.amountCents }),
      ...(opts.reason && { reason: opts.reason }),
    }),
  });
}
```

## 8. Endpoints admin — cancel + refund

`app/api/admin/pagou/transactions/[id]/cancel/route.ts`:

```ts
import { NextResponse } from "next/server";
import { cancelTransaction } from "@/lib/pagou/pix";
import { prisma } from "@/lib/prisma";
import { requireAdmin } from "@/lib/auth"; // adapter ao auth do projeto

export async function POST(_req: Request, { params }: { params: { id: string } }) {
  await requireAdmin();

  try {
    const tx = await cancelTransaction(params.id);
    await prisma.pagouPixTransaction.updateMany({
      where: { pagouTransactionId: params.id },
      data: { status: tx.status },
    });
    return NextResponse.json({ ok: true, status: tx.status });
  } catch (e) {
    console.error("[pagou/admin/cancel]", { id: params.id, message: (e as Error).message });
    return NextResponse.json({ error: "cancel failed" }, { status: 502 });
  }
}
```

`app/api/admin/pagou/transactions/[id]/refund/route.ts`:

```ts
import { NextResponse } from "next/server";
import { refundTransaction } from "@/lib/pagou/pix";
import { prisma } from "@/lib/prisma";
import { requireAdmin } from "@/lib/auth";

export async function POST(req: Request, { params }: { params: { id: string } }) {
  const adminUser = await requireAdmin();
  const body = (await req.json().catch(() => ({}))) as { amountCents?: number; reason?: string };

  try {
    const tx = await refundTransaction(params.id, body);

    await prisma.pagouPixTransaction.updateMany({
      where: { pagouTransactionId: params.id },
      data: { status: tx.status },
    });

    // Auditoria
    console.info("[pagou.refund.requested]", {
      transaction_id: params.id,
      admin_user_id: adminUser.id,
      amount_cents: body.amountCents ?? null,
      reason: body.reason ?? null,
    });

    return NextResponse.json({ ok: true, status: tx.status });
  } catch (e) {
    console.error("[pagou/admin/refund]", { id: params.id, message: (e as Error).message });
    return NextResponse.json({ error: "refund failed" }, { status: 502 });
  }
}
```

> A confirmação real do refund chega pelo **webhook `transaction.refunded`** (ou `.partially_refunded`). O endpoint admin apenas dispara o estorno e atualiza o status crú; a libertação de valor / ajuste do pedido acontece quando o webhook chegar.

## 5. Status mapping

`src/lib/pagou/status.ts`:

```ts
export const PAGOU_STATUS = {
  pending: "aguardando_pagamento",
  paid: "pago",
  expired: "expirado",
  canceled: "cancelado",
  refused: "recusado",
  refunded: "estornado",
  partially_refunded: "estornado_parcial",
  chargedback: "chargeback",
} as const;

export type PagouStatus = keyof typeof PAGOU_STATUS;
export type InternalStatus = (typeof PAGOU_STATUS)[PagouStatus];

export function mapStatus(s: string): InternalStatus | "desconhecido" {
  return (PAGOU_STATUS as Record<string, InternalStatus>)[s] ?? "desconhecido";
}
```

> Ajustar os valores para os status internos definidos pelo usuário durante a fase de descoberta.

## 6. Endpoint público — criar cobrança (App Router)

`app/api/pagou/pix/route.ts`:

```ts
import { NextResponse } from "next/server";
import { createPixCharge } from "@/lib/pagou/pix";
import { prisma } from "@/lib/prisma";

export async function POST(req: Request) {
  try {
    const body = await req.json();
    const { orderId } = body as { orderId: string };

    const order = await prisma.order.findUnique({ where: { id: orderId } });
    if (!order) {
      return NextResponse.json({ error: "Order not found" }, { status: 404 });
    }

    const tx = await createPixCharge({
      externalRef: order.id,
      amountCents: order.amountCents,
      buyer: {
        name: order.buyerName,
        email: order.buyerEmail,
        document: { type: "CPF", number: order.buyerDocument },
      },
    });

    await prisma.pagouPixTransaction.upsert({
      where: { externalRef: order.id },
      create: {
        pagouTransactionId: tx.id,
        externalRef: order.id,
        orderId: order.id,
        amountCents: order.amountCents,
        currency: "BRL",
        status: tx.status,
        pixQrCode: tx.pix_qr_code,
        pixCode: tx.pix_code,
        rawResponse: tx as never,
      },
      update: {
        pagouTransactionId: tx.id,
        status: tx.status,
        pixQrCode: tx.pix_qr_code,
        pixCode: tx.pix_code,
        rawResponse: tx as never,
      },
    });

    return NextResponse.json({
      transactionId: tx.id,
      status: tx.status,
      pixQrCode: tx.pix_qr_code,
      pixCode: tx.pix_code,
    });
  } catch (e) {
    console.error("[pagou/pix] error", { message: (e as Error).message });
    return NextResponse.json({ error: "Internal error" }, { status: 500 });
  }
}
```

### Variante — Pages Router

`pages/api/pagou/pix.ts`:

```ts
import type { NextApiRequest, NextApiResponse } from "next";
import { createPixCharge } from "@/lib/pagou/pix";
import { prisma } from "@/lib/prisma";

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  if (req.method !== "POST") return res.status(405).end();
  // ... mesmo corpo da versão App Router
}
```

## 7. Webhook (com verificação HMAC)

`src/lib/pagou/signature.ts`:

```ts
import { createHmac, timingSafeEqual } from "node:crypto";

export function verifyPagouSignature(rawBody: string, headerSignature: string | null): boolean {
  const secret = process.env.PAGOU_WEBHOOK_SECRET;
  if (!secret) {
    if (process.env.PAGOU_ENV === "production") {
      throw new Error("PAGOU_WEBHOOK_SECRET is required in production");
    }
    console.warn("[pagou] PAGOU_WEBHOOK_SECRET not set — signature check skipped (dev only)");
    return true;
  }
  if (!headerSignature) return false;

  const expected = createHmac("sha256", secret).update(rawBody, "utf8").digest("hex");
  const a = Buffer.from(expected, "hex");
  const b = Buffer.from(headerSignature.replace(/^sha256=/, ""), "hex");
  if (a.length !== b.length) return false;
  try {
    return timingSafeEqual(a, b);
  } catch {
    return false;
  }
}
```

`app/api/webhooks/pagou/route.ts`:

```ts
import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { mapStatus } from "@/lib/pagou/status";
import { verifyPagouSignature } from "@/lib/pagou/signature";

type PagouTransactionEvent = {
  id: string;
  event: "transaction";
  data: {
    event_type: string;
    id: string;
    status: string;
    correlation_id?: string;
  };
};

export async function POST(req: Request) {
  const rawBody = await req.text();
  const signature = req.headers.get("x-pagou-signature");

  if (!verifyPagouSignature(rawBody, signature)) {
    return NextResponse.json({ error: "invalid signature" }, { status: 401 });
  }

  let payload: PagouTransactionEvent;
  try {
    payload = JSON.parse(rawBody) as PagouTransactionEvent;
  } catch {
    return NextResponse.json({ received: false }, { status: 400 });
  }

  if (payload.event !== "transaction" || !payload.id) {
    return NextResponse.json({ received: true });
  }

  try {
    await prisma.pagouWebhookEvent.create({
      data: {
        eventId: payload.id,
        eventType: payload.data.event_type,
        resourceId: payload.data.id,
        correlationId: payload.data.correlation_id,
        payload: payload as never,
      },
    });
  } catch (e) {
    return NextResponse.json({ received: true });
  }

  void processEventAsync(payload);

  return NextResponse.json({ received: true });
}

async function processEventAsync(event: PagouTransactionEvent) {
  try {
    const internal = mapStatus(event.data.status);
    await prisma.pagouPixTransaction.updateMany({
      where: { pagouTransactionId: event.data.id },
      data: { status: event.data.status },
    });

    if (event.data.event_type === "transaction.paid") {
      await prisma.order.updateMany({
        where: { id: event.data.correlation_id ?? "" },
        data: { status: internal },
      });
    }

    await prisma.pagouWebhookEvent.updateMany({
      where: { eventId: event.id },
      data: { processedAt: new Date() },
    });
  } catch (e) {
    console.error("[pagou/webhook] processing error", {
      eventId: event.id,
      message: (e as Error).message,
    });
  }
}
```

> Em produção, em vez de `void processEventAsync(...)`, use Inngest, Trigger.dev, Vercel Queue, ou enfileire em Redis/SQS. Webhook handler precisa retornar < 5s.

## 8. Testes

`tests/pagou/pix.test.ts` (Vitest):

```ts
import { describe, it, expect, vi } from "vitest";
import { mapStatus } from "@/lib/pagou/status";

describe("mapStatus", () => {
  it("maps paid", () => expect(mapStatus("paid")).toBe("pago"));
  it("maps pending", () => expect(mapStatus("pending")).toBe("aguardando_pagamento"));
  it("handles unknown", () => expect(mapStatus("alien")).toBe("desconhecido"));
});

describe("webhook dedupe", () => {
  it("inserts once for same event_id", async () => {
    // setup with sqlite in-memory or testcontainers
  });
});
```

`tests/pagou/webhook.e2e.test.ts`:

```ts
// POST /api/webhooks/pagou twice with same event_id and assert idempotent state
```

## 9. Frontend

### Hook React + componente

`src/hooks/usePagouPix.ts`:

```ts
"use client";

import { useEffect, useRef, useState } from "react";

export type PagouPixState =
  | { status: "idle" }
  | { status: "creating" }
  | { status: "waiting"; qrCode: string; pixCode: string; transactionId: string }
  | { status: "paid" }
  | { status: "error"; message: string };

export function usePagouPix(orderId: string | null) {
  const [state, setState] = useState<PagouPixState>({ status: "idle" });
  const pollRef = useRef<number | null>(null);

  useEffect(() => () => {
    if (pollRef.current) window.clearInterval(pollRef.current);
  }, []);

  async function start() {
    if (!orderId) return;
    setState({ status: "creating" });

    const res = await fetch("/api/pagou/pix", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ orderId }),
    });

    if (!res.ok) {
      setState({ status: "error", message: `HTTP ${res.status}` });
      return;
    }

    const data = await res.json();
    setState({
      status: "waiting",
      qrCode: data.pixQrCode,
      pixCode: data.pixCode,
      transactionId: data.transactionId,
    });

    // Polling do nosso BACKEND (não da Pagou) — o backend é atualizado por webhook
    pollRef.current = window.setInterval(async () => {
      const r = await fetch(`/api/orders/${orderId}/status`);
      const o = await r.json();
      if (o.status === "pago") {
        if (pollRef.current) window.clearInterval(pollRef.current);
        setState({ status: "paid" });
      }
    }, 3000);
  }

  return { state, start };
}
```

`src/components/PixCheckout.tsx`:

```tsx
"use client";

import { useState } from "react";
import { usePagouPix } from "@/hooks/usePagouPix";

export function PixCheckout({ orderId }: { orderId: string }) {
  const { state, start } = usePagouPix(orderId);
  const [copied, setCopied] = useState(false);

  if (state.status === "idle") {
    return <button onClick={start}>Pagar com PIX</button>;
  }

  if (state.status === "creating") {
    return <p>A gerar QR Code…</p>;
  }

  if (state.status === "waiting") {
    return (
      <div>
        <h3>Pague com PIX</h3>

        {/* ⚠️ O QR Code base64 vem SEM prefixo MIME — adicionar manualmente */}
        <img
          src={`data:image/png;base64,${state.qrCode}`}
          alt="PIX QR Code"
          style={{ width: 280, height: 280 }}
        />

        <p>Ou copia o código abaixo:</p>
        <textarea readOnly value={state.pixCode} style={{ width: "100%", height: 80 }} />
        <button
          onClick={() => {
            navigator.clipboard.writeText(state.pixCode);
            setCopied(true);
            setTimeout(() => setCopied(false), 2000);
          }}
        >
          {copied ? "✓ Copiado" : "Copiar PIX"}
        </button>

        <p>A verificar pagamento…</p>
      </div>
    );
  }

  if (state.status === "paid") {
    return <p>✓ Pagamento confirmado!</p>;
  }

  return <p style={{ color: "red" }}>Erro: {state.message}</p>;
}
```

> **Importante:** o polling no frontend é contra `/api/orders/:id/status` (estado **interno** do pedido), **nunca** contra a API da Pagou. O backend é atualizado pelo webhook — o frontend apenas consulta o resultado.

## 10. Verificação

```bash
npm run build
npm test
npx prisma migrate status
```
