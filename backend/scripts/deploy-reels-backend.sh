#!/usr/bin/env bash
set -euo pipefail

BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$BACKEND_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE" >&2
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

: "${NEXT_PUBLIC_SUPABASE_URL:?Missing NEXT_PUBLIC_SUPABASE_URL}"
: "${APIFY_TOKEN:?Missing APIFY_TOKEN}"
: "${OPENAI_API_KEY:?Missing OPENAI_API_KEY}"
: "${SUPABASE_SERVICE_ROLE_KEY:?Missing SUPABASE_SERVICE_ROLE_KEY}"
: "${SUPABASE_ACCESS_TOKEN:?Missing SUPABASE_ACCESS_TOKEN}"

export SUPABASE_ACCESS_TOKEN

PROJECT_REF="$(node -e 'const u=new URL(process.env.NEXT_PUBLIC_SUPABASE_URL); console.log(u.hostname.split(".")[0])')"
if [[ -n "${SUPABASE_BIN:-}" ]]; then
  read -r -a SUPABASE_CMD <<< "$SUPABASE_BIN"
else
  SUPABASE_CMD=(npx -y supabase)
fi

cd "$BACKEND_DIR"

"${SUPABASE_CMD[@]}" secrets set \
  NEXT_PUBLIC_SUPABASE_URL="$NEXT_PUBLIC_SUPABASE_URL" \
  SERVICE_ROLE_KEY="$SUPABASE_SERVICE_ROLE_KEY" \
  APIFY_TOKEN="$APIFY_TOKEN" \
  OPENAI_API_KEY="$OPENAI_API_KEY" \
  --project-ref "$PROJECT_REF"

"${SUPABASE_CMD[@]}" link --project-ref "$PROJECT_REF"
"${SUPABASE_CMD[@]}" db push --linked
"${SUPABASE_CMD[@]}" functions deploy reels --project-ref "$PROJECT_REF"
