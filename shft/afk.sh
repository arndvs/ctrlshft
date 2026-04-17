#!/usr/bin/env bash

# AFK shft — autonomous loop consuming GitHub issues backlog.
# Usage: ./shft/afk.sh [max_iterations]
# Default: 5 iterations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTRL_DIR="$(dirname "$SCRIPT_DIR")"
MAX_ITERATIONS="${1:-5}"
LOCKDIR="/tmp/shft-afk.lock"
MINT_SCRIPT="$CTRL_DIR/bin/mint_github_app_token.py"
RUN_WITH_SECRETS="$CTRL_DIR/bin/run-with-secrets.sh"
VENV_DIR="$CTRL_DIR/secrets/.venv"

source "$CTRL_DIR/bin/_lib.sh"

# Concurrency guard — mkdir is atomic and portable (no flock on macOS)
if ! mkdir "$LOCKDIR" 2>/dev/null; then
    echo "shft already running" >&2
    exit 1
fi
trap 'rmdir "$LOCKDIR" 2>/dev/null' EXIT

if [[ ! -x "$RUN_WITH_SECRETS" ]]; then
    echo "ERROR: $RUN_WITH_SECRETS not found or not executable" >&2
    exit 1
fi

if [[ ! -f "$MINT_SCRIPT" ]]; then
    echo "ERROR: $MINT_SCRIPT not found. Merge AFK credential rotation slices before running AFK." >&2
    exit 1
fi

if ! find_python; then
    echo "ERROR: python3/python not found. Required for GitHub App token mint helper." >&2
    exit 1
fi
PYTHON_BIN="$PYTHON"

if ! "$RUN_WITH_SECRETS" bash "$CTRL_DIR/bin/validate-env.sh" --afk; then
    echo "ERROR: AFK environment validation failed" >&2
    exit 1
fi

for i in $(seq 1 "$MAX_ITERATIONS"); do
    echo "=== shft iteration $i of $MAX_ITERATIONS ==="

    mint_json=$("$RUN_WITH_SECRETS" "$PYTHON_BIN" "$MINT_SCRIPT") || {
        echo "ERROR: failed to mint GitHub App token for iteration $i" >&2
        exit 1
    }

    afk_token=$(printf '%s' "$mint_json" | jq -r '.token // empty')
    afk_token_expires_at=$(printf '%s' "$mint_json" | jq -r '.expires_at // empty')

    if [[ -z "$afk_token" ]]; then
        echo "ERROR: token mint helper returned empty token for iteration $i" >&2
        exit 1
    fi

    if [[ -z "$afk_token_expires_at" ]]; then
        echo "ERROR: token mint helper returned empty expires_at for iteration $i" >&2
        exit 1
    fi

    echo "token minted for iteration $i (expires_at=$afk_token_expires_at)"

    source "$SCRIPT_DIR/_build_prompt.sh"
    trap 'rm -f "$PROMPT_FILE"; rmdir "$LOCKDIR" 2>/dev/null' EXIT
    raw_output=$(mktemp)
    trap 'rm -f "$raw_output" "$PROMPT_FILE"; rmdir "$LOCKDIR" 2>/dev/null' EXIT

    if ! GITHUB_TOKEN="$afk_token" srt claude \
        --print \
        --output-format stream-json \
        < "$PROMPT_FILE" \
        2>/dev/null | tee /dev/stderr > "$raw_output"; then
        echo "ERROR: srt failed on iteration $i" >&2
        exit 1
    fi

    unset afk_token

    result=$(jq -r 'select(.type == "text") | .content' < "$raw_output" 2>/dev/null || true)
    rm -f "$raw_output" "$PROMPT_FILE"

    if echo "$result" | grep -q '<promise>NO MORE TASKS</promise>'; then
        echo "shft complete after $i iterations"
        exit 0
    fi
done

echo "shft reached max iterations ($MAX_ITERATIONS)"
