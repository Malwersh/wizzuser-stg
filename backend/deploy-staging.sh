#!/usr/bin/env bash
set -euo pipefail

# Deploy WizzUser backend (staging) with required Central notifications internal key.
#
# This key must match the Notifications service's NOTIFICATIONS_INTERNAL_KEY
# (used to authorize calls to endpoints like /push/send/merchant-order).
#
# Usage:
#   # Option A (recommended): let the script fetch it from Secrets Manager
#   ./deploy-staging.sh
#
#   # Option B: provide it explicitly
#   export CENTRAL_NOTIFICATIONS_INTERNAL_KEY='...'
#   ./deploy-staging.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

STAGE="staging"
AWS_REGION_DEFAULT="us-east-1"

# Optional: load key from Secrets Manager to avoid manual copy/paste.
CENTRAL_NOTIFICATIONS_INTERNAL_KEY_SECRET_ID="${CENTRAL_NOTIFICATIONS_INTERNAL_KEY_SECRET_ID:-wizz/${STAGE}/notifications/internal-key}"
AWS_PROFILE="${AWS_PROFILE:-Wizz_stg_UserApp}"
AWS_REGION="${AWS_REGION:-$AWS_REGION_DEFAULT}"

get_secret_string() {
  local secret_id="$1"
  aws secretsmanager get-secret-value \
    --secret-id "$secret_id" \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" \
    --query 'SecretString' \
    --output text 2>/dev/null || true
}

if [[ -z "${CENTRAL_NOTIFICATIONS_INTERNAL_KEY:-}" ]]; then
  candidate="$(get_secret_string "$CENTRAL_NOTIFICATIONS_INTERNAL_KEY_SECRET_ID")"
  if [[ -n "$candidate" && "$candidate" != "None" && "$candidate" != "null" ]]; then
    export CENTRAL_NOTIFICATIONS_INTERNAL_KEY="$candidate"
  fi
fi

if [[ -z "${CENTRAL_NOTIFICATIONS_INTERNAL_KEY:-}" ]]; then
  echo "🔐 CENTRAL_NOTIFICATIONS_INTERNAL_KEY is required to send merchant push notifications."
  echo "   Tried Secrets Manager: $CENTRAL_NOTIFICATIONS_INTERNAL_KEY_SECRET_ID"
  echo "   Tip: export CENTRAL_NOTIFICATIONS_INTERNAL_KEY='...'"
  exit 1
fi

# Optional overrides (defaults are defined in template.yaml)
CENTRAL_NOTIFICATIONS_BASE_URL="${CENTRAL_NOTIFICATIONS_BASE_URL:-}"

PARAM_OVERRIDES=(
  "Environment=${STAGE}"
  "CentralNotificationsInternalKey=${CENTRAL_NOTIFICATIONS_INTERNAL_KEY}"
)

if [[ -n "$CENTRAL_NOTIFICATIONS_BASE_URL" ]]; then
  PARAM_OVERRIDES+=("CentralNotificationsBaseUrl=${CENTRAL_NOTIFICATIONS_BASE_URL}")
fi

echo "🚀 Deploying WizzUser backend (staging)…"

echo "🔧 Building (sam build)…"

sam build

sam deploy \
  --config-env staging \
  --template-file .aws-sam/build/template.yaml \
  --parameter-overrides "${PARAM_OVERRIDES[@]}"

echo "✅ Done."
