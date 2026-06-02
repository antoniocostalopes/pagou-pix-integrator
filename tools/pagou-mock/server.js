#!/usr/bin/env node
// Pagou Mock Server — stand-in for the Pagou.ai v2 API for local development.
// Zero dependencies; Node 20+.

import http from "node:http";
import crypto from "node:crypto";

const PORT = Number(process.env.PORT) || 4242;
const WEBHOOK_URL = process.env.WEBHOOK_URL || "http://localhost:3000/api/webhooks/pagou";
const WEBHOOK_SECRET = process.env.WEBHOOK_SECRET || "dev-secret-please-change";
const WEBHOOK_DELAY_MS = Number(process.env.WEBHOOK_DELAY_MS) || 2000;

// In-memory store keyed by transaction id
const transactions = new Map();

// 1x1 transparent PNG, base64 (so the QR placeholder is renderable)
const PLACEHOLDER_QR_BASE64 =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=";

function newId(prefix) {
  return prefix + "_" + crypto.randomBytes(8).toString("hex");
}

function deriveScenario(externalRef = "") {
  if (externalRef.startsWith("expire-")) return "expire";
  if (externalRef.startsWith("refuse-")) return "refuse";
  if (externalRef.startsWith("chargeback-")) return "chargeback";
  if (externalRef.startsWith("slow-")) return "slow";
  if (externalRef.startsWith("silent-")) return "silent";
  return "happy";
}

async function readJson(req) {
  return new Promise((resolve, reject) => {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      try {
        resolve(body ? JSON.parse(body) : {});
      } catch (e) {
        reject(e);
      }
    });
    req.on("error", reject);
  });
}

function send(res, code, body) {
  res.writeHead(code, { "Content-Type": "application/json" });
  res.end(JSON.stringify(body));
}

async function postWebhook(payload) {
  const body = JSON.stringify(payload);
  const signature = crypto.createHmac("sha256", WEBHOOK_SECRET).update(body).digest("hex");

  const url = new URL(WEBHOOK_URL);
  const opts = {
    method: "POST",
    hostname: url.hostname,
    port: url.port || (url.protocol === "https:" ? 443 : 80),
    path: url.pathname + url.search,
    headers: {
      "Content-Type": "application/json",
      "Content-Length": Buffer.byteLength(body),
      "X-Pagou-Signature": signature,
    },
  };

  return new Promise((resolve) => {
    const client = url.protocol === "https:" ? import("node:https") : import("node:http");
    client.then(({ default: mod }) => {
      const req = mod.request(opts, (res) => {
        let chunks = "";
        res.on("data", (c) => (chunks += c));
        res.on("end", () => {
          console.log(`  → webhook ${payload.id} (${payload.data.event_type}) → ${res.statusCode}`);
          resolve();
        });
      });
      req.on("error", (e) => {
        console.error(`  → webhook failed: ${e.message}`);
        resolve();
      });
      req.write(body);
      req.end();
    });
  });
}

function makeEvent(eventType, transaction) {
  return {
    id: newId("evt_pay"),
    event: "transaction",
    data: {
      event_type: eventType,
      id: transaction.id,
      status: transaction.status,
      correlation_id: transaction.external_ref,
    },
  };
}

async function simulateLifecycle(transaction) {
  const scenario = deriveScenario(transaction.external_ref);

  if (scenario === "silent") {
    console.log(`  (scenario=silent: no webhooks for ${transaction.id})`);
    return;
  }

  const delay = scenario === "slow" ? 30000 : WEBHOOK_DELAY_MS;

  // pending
  await sleep(delay);
  transaction.status = "pending";
  await postWebhook(makeEvent("transaction.pending", transaction));

  // terminal
  await sleep(delay);
  switch (scenario) {
    case "expire":
      transaction.status = "expired";
      await postWebhook(makeEvent("transaction.expired", transaction));
      break;
    case "refuse":
      transaction.status = "refused";
      await postWebhook(makeEvent("transaction.refused", transaction));
      break;
    case "chargeback":
      transaction.status = "paid";
      await postWebhook(makeEvent("transaction.paid", transaction));
      await sleep(30000);
      transaction.status = "chargedback";
      await postWebhook(makeEvent("transaction.chargedback", transaction));
      break;
    default:
      transaction.status = "paid";
      await postWebhook(makeEvent("transaction.paid", transaction));
  }
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);

  // CORS for local dev
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
  if (req.method === "OPTIONS") {
    res.writeHead(204);
    res.end();
    return;
  }

  console.log(`${req.method} ${url.pathname}`);

  // POST /v2/transactions
  if (req.method === "POST" && url.pathname === "/v2/transactions") {
    try {
      const body = await readJson(req);
      const id = newId("tr");
      const transaction = {
        id,
        status: "pending",
        external_ref: body.external_ref,
        amount: body.amount,
        currency: body.currency || "BRL",
        method: body.method,
        pix_qr_code: PLACEHOLDER_QR_BASE64,
        pix_code: "00020126" + crypto.randomBytes(48).toString("hex"),
      };
      transactions.set(id, transaction);
      send(res, 201, transaction);
      // Fire-and-forget lifecycle simulation
      simulateLifecycle(transaction).catch(console.error);
    } catch (e) {
      send(res, 400, { error: e.message });
    }
    return;
  }

  // GET /v2/transactions/:id
  const txGet = url.pathname.match(/^\/v2\/transactions\/(tr_[a-f0-9]+)$/);
  if (req.method === "GET" && txGet) {
    const t = transactions.get(txGet[1]);
    if (!t) return send(res, 404, { error: "not found" });
    return send(res, 200, t);
  }

  // POST /v2/transactions/:id/cancel
  const txCancel = url.pathname.match(/^\/v2\/transactions\/(tr_[a-f0-9]+)\/cancel$/);
  if (req.method === "POST" && txCancel) {
    const t = transactions.get(txCancel[1]);
    if (!t) return send(res, 404, { error: "not found" });
    if (t.status !== "pending") return send(res, 409, { error: "cannot cancel in current state", status: t.status });
    t.status = "canceled";
    send(res, 200, t);
    postWebhook(makeEvent("transaction.cancelled", t)).catch(console.error);
    return;
  }

  // POST /v2/transactions/:id/refund
  const txRefund = url.pathname.match(/^\/v2\/transactions\/(tr_[a-f0-9]+)\/refund$/);
  if (req.method === "POST" && txRefund) {
    const t = transactions.get(txRefund[1]);
    if (!t) return send(res, 404, { error: "not found" });
    if (t.status !== "paid" && t.status !== "partially_refunded") {
      return send(res, 409, { error: "cannot refund in current state", status: t.status });
    }
    const body = await readJson(req);
    const partial = body.amount && body.amount < t.amount;
    t.status = partial ? "partially_refunded" : "refunded";
    send(res, 200, t);
    postWebhook(
      makeEvent(partial ? "transaction.partially_refunded" : "transaction.refunded", t),
    ).catch(console.error);
    return;
  }

  send(res, 404, { error: "route not found" });
});

server.listen(PORT, () => {
  console.log(`Pagou Mock listening on http://localhost:${PORT}`);
  console.log(`Webhooks will be sent to ${WEBHOOK_URL}`);
  console.log(`HMAC secret: ${WEBHOOK_SECRET}`);
  console.log(`Default delay between events: ${WEBHOOK_DELAY_MS}ms`);
});
