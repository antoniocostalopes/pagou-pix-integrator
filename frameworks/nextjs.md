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
```

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

## 7. Webhook

`app/api/webhooks/pagou/route.ts`:

```ts
import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { mapStatus } from "@/lib/pagou/status";

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
  let payload: PagouTransactionEvent;
  try {
    payload = (await req.json()) as PagouTransactionEvent;
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

## 9. Verificação

```bash
npm run build
npm test
npx prisma migrate status
```
