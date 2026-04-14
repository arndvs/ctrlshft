#!/usr/bin/env bash

# verify-github-app-token.sh — Pretty, token-safe GitHub App token smoke test.
#
# Prints only safe metadata (success, expires_at, token length), never raw token.
# Uses process-scoped secrets via run-with-secrets.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTRL_DIR="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/_lib.sh"

RUN_WITH_SECRETS="$SCRIPT_DIR/run-with-secrets.sh"
MINT_SCRIPT="$SCRIPT_DIR/mint_github_app_token.py"
VENV_DIR="$CTRL_DIR/secrets/.venv"

if [[ ! -x "$RUN_WITH_SECRETS" ]]; then
    red "ERROR: $RUN_WITH_SECRETS not found or not executable"
    exit 1
fi

if [[ ! -f "$MINT_SCRIPT" ]]; then
    red "ERROR: $MINT_SCRIPT not found"
    exit 1
fi

find_venv_python

PYTHON_BIN=""
if [[ -n "${_venv_python:-}" ]] && "$_venv_python" --version >/dev/null 2>&1; then
    PYTHON_BIN="$_venv_python"
elif command -v python3 >/dev/null 2>&1 && python3 --version >/dev/null 2>&1; then
    PYTHON_BIN="python3"
elif command -v python >/dev/null 2>&1 && python --version >/dev/null 2>&1; then
    PYTHON_BIN="python"
else
    red "ERROR: No working Python found. Re-run: bash ~/dotfiles/bin/bootstrap.sh"
    exit 1
fi

echo "================================================"
echo "GitHub App Token Smoke Test (safe output)"
echo "================================================"

mint_out="$(mktemp)"
mint_err="$(mktemp)"
trap 'rm -f "$mint_out" "$mint_err" 2>/dev/null' EXIT

if ! "$RUN_WITH_SECRETS" "$PYTHON_BIN" "$MINT_SCRIPT" >"$mint_out" 2>"$mint_err"; then
    red "  ✗ Mint failed"
    if [[ -s "$mint_err" ]]; then
        sed 's/^/    /' "$mint_err"
    fi
    exit 1
fi

parsed="$($PYTHON_BIN - <<'PY' "$mint_out"
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8", errors="ignore") as f:
    data = json.load(f)

token = str(data.get("token", ""))
expires_at = str(data.get("expires_at", ""))

if not token or not expires_at:
    raise SystemExit(2)

print(expires_at)
print(len(token))
PY
)" || {
    red "  ✗ Mint output parse failed"
    exit 1
}

expires_at="$(printf '%s\n' "$parsed" | sed -n '1p')"
token_len="$(printf '%s\n' "$parsed" | sed -n '2p')"

green "  ✓ mint_success=yes"
echo "    expires_at=$expires_at"
echo "    token_len=$token_len"
echo "================================================"
