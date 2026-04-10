#!/usr/bin/env bash

# AFK shift — autonomous loop consuming GitHub issues backlog.
# Usage: ./shift/afk.sh [max_iterations]
# Default: 5 iterations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTRL_DIR="$(dirname "$SCRIPT_DIR")"
MAX_ITERATIONS="${1:-5}"
LOCKFILE="/tmp/shift-afk.lock"

# Concurrency guard — flock auto-releases on exit/crash (no stale PID issue)
exec 200>"$LOCKFILE"

if ! flock -n 200; then
    echo "shift already running" >&2
    exit 1
fi

for i in $(seq 1 "$MAX_ITERATIONS"); do
    echo "=== shift iteration $i of $MAX_ITERATIONS ==="

    source "$SCRIPT_DIR/_build_prompt.sh"
    raw_output=$(mktemp)
    trap 'rm -f "$raw_output" "$PROMPT_FILE"' EXIT

    if ! cat "$PROMPT_FILE" | sbx run --name shift-afk claude . "$CTRL_DIR:ro" \
        -- --print \
        --output-format stream-json \
        2>/dev/null | tee /dev/stderr > "$raw_output"; then
        echo "ERROR: sbx failed on iteration $i" >&2
        exit 1
    fi

    result=$(jq -r 'select(.type == "text") | .content' < "$raw_output" 2>/dev/null || true)
    rm -f "$raw_output" "$PROMPT_FILE"

    if echo "$result" | grep -q '<promise>NO MORE TASKS</promise>'; then
        echo "shift complete after $i iterations"
        exit 0
    fi
done

echo "shift reached max iterations ($MAX_ITERATIONS)"
