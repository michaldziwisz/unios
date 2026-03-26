#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_PATH="${1:-$ROOT_DIR/Config/TelegramSecrets.xcconfig}"
POSTMASTER_ROOT="${POSTMASTER_ROOT:-/mnt/d/projekty/postmaster}"
POSTMASTER_API_FILE="${POSTMASTER_API_FILE:-$POSTMASTER_ROOT/postmaster_api.txt}"

api_id="${TELEGRAM_API_ID:-${POSTMASTER_API_ID:-}}"
api_hash="${TELEGRAM_API_HASH:-${POSTMASTER_API_HASH:-}}"
use_test_dc="${TELEGRAM_USE_TEST_DC:-NO}"

if [[ -z "$api_id" || -z "$api_hash" ]] && [[ -f "$POSTMASTER_API_FILE" ]]; then
  parsed_credentials="$(
    python3 - "$POSTMASTER_API_FILE" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="replace")
lines = [line.rstrip("\n") for line in text.splitlines()]


def first_non_empty_line_after(start_index: int) -> str | None:
    for value in lines[start_index + 1:]:
        stripped = value.strip()
        if stripped:
            return stripped
    return None


api_id = None
api_hash = None

for index, line in enumerate(lines):
    normalized = line.strip().lower()

    if api_id is None and "api_id" in normalized:
        match = re.search(r"\bapi_id\b\s*[:=]\s*(\d+)", normalized)
        if match:
            api_id = match.group(1)
        else:
            candidate = first_non_empty_line_after(index)
            if candidate and re.fullmatch(r"\d+", candidate):
                api_id = candidate

    if api_hash is None and "api_hash" in normalized:
        match = re.search(r"\bapi_hash\b\s*[:=]\s*([0-9a-f]{32,})", normalized)
        if match:
            api_hash = match.group(1)
        else:
            candidate = first_non_empty_line_after(index)
            if candidate and re.fullmatch(r"[0-9a-fA-F]{32,}", candidate):
                api_hash = candidate

    if api_id and api_hash:
        break

print(api_id or "")
print(api_hash or "")
PY
  )"

  if [[ -z "$api_id" ]]; then
    api_id="$(printf '%s\n' "$parsed_credentials" | sed -n '1p')"
  fi

  if [[ -z "$api_hash" ]]; then
    api_hash="$(printf '%s\n' "$parsed_credentials" | sed -n '2p')"
  fi
fi

if [[ -z "$api_id" || -z "$api_hash" ]]; then
  echo "Missing Telegram credentials. Set TELEGRAM_API_ID and TELEGRAM_API_HASH, or provide $POSTMASTER_API_FILE." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"
cat > "$OUTPUT_PATH" <<EOF
TELEGRAM_API_ID = $api_id
TELEGRAM_API_HASH = $api_hash
TELEGRAM_USE_TEST_DC = $use_test_dc
EOF

echo "Wrote $(basename "$OUTPUT_PATH")."
