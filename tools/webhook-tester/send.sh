#!/usr/bin/env bash
# Send a simulated Pagou webhook event with valid HMAC signature.
# Usage: ./send.sh <event_name>
#   event_name: paid | pending | created | cancelled | expired | refused |
#               refunded | partial_refunded | chargedback
set -euo pipefail

EVENT_NAME="${1:-paid}"
WEBHOOK_URL="${WEBHOOK_URL:-http://localhost:3000/api/webhooks/pagou}"
WEBHOOK_SECRET="${WEBHOOK_SECRET:-dev-secret-please-change}"
EXTERNAL_REF="${EXTERNAL_REF:-order_test_1001}"
TRANSACTION_ID="${TRANSACTION_ID:-tr_test_1001}"
EVENT_ID="${EVENT_ID:-evt_test_$(date +%s)}"

# Map shorthand -> event_type + status
case "$EVENT_NAME" in
  created)          EVENT_TYPE="transaction.created";          STATUS="pending" ;;
  pending)          EVENT_TYPE="transaction.pending";          STATUS="pending" ;;
  paid)             EVENT_TYPE="transaction.paid";             STATUS="paid" ;;
  cancelled)        EVENT_TYPE="transaction.cancelled";        STATUS="canceled" ;;
  expired)          EVENT_TYPE="transaction.expired";          STATUS="expired" ;;
  refused)          EVENT_TYPE="transaction.refused";          STATUS="refused" ;;
  refunded)         EVENT_TYPE="transaction.refunded";         STATUS="refunded" ;;
  partial_refunded) EVENT_TYPE="transaction.partially_refunded"; STATUS="partially_refunded" ;;
  chargedback)      EVENT_TYPE="transaction.chargedback";      STATUS="chargedback" ;;
  *)
    echo "Unknown event: $EVENT_NAME" >&2
    echo "Use one of: created|pending|paid|cancelled|expired|refused|refunded|partial_refunded|chargedback" >&2
    exit 1
    ;;
esac

PAYLOAD=$(cat <<EOF
{"id":"$EVENT_ID","event":"transaction","data":{"event_type":"$EVENT_TYPE","id":"$TRANSACTION_ID","status":"$STATUS","correlation_id":"$EXTERNAL_REF"}}
EOF
)

# HMAC-SHA256 of the raw body, hex digest
SIGNATURE=$(printf '%s' "$PAYLOAD" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | awk '{print $2}')

echo "→ $WEBHOOK_URL"
echo "  event_id    : $EVENT_ID"
echo "  event_type  : $EVENT_TYPE"
echo "  status      : $STATUS"
echo "  signature   : ${SIGNATURE:0:16}..."

HTTP_CODE=$(curl -s -o /tmp/pagou-webhook-resp.txt -w "%{http_code}" \
  -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -H "X-Pagou-Signature: $SIGNATURE" \
  -d "$PAYLOAD")

echo "← HTTP $HTTP_CODE"
echo "  body: $(cat /tmp/pagou-webhook-resp.txt 2>/dev/null || echo '(empty)')"
