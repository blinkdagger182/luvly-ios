#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT_DIR/backend/.env"
OUTPUT_FILE="$ROOT_DIR/iOS, visionOS/🎞️Reels/ReelBackendConfig.generated.swift"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE" >&2
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

: "${NEXT_PUBLIC_SUPABASE_URL:?Missing NEXT_PUBLIC_SUPABASE_URL}"
: "${NEXT_PUBLIC_SUPABASE_ANON_KEY:?Missing NEXT_PUBLIC_SUPABASE_ANON_KEY}"

cat > "$OUTPUT_FILE" <<EOF
import Foundation

enum ReelBackendConfig {
    static let supabaseURL = "${NEXT_PUBLIC_SUPABASE_URL}"
    static let supabaseAnonKey = "${NEXT_PUBLIC_SUPABASE_ANON_KEY}"
}
EOF
