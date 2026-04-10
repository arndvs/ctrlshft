#!/usr/bin/env bash

# AFK shift — autonomous loop consuming GitHub issues backlog.
# Usage: ./shift/afk.sh [max_iterations]
# Default: 5 iterations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTRL_DIR="$(dirname "$SCRIPT_DIR")"
MAX_ITERATIONS="${1:-5}"
LOCKFILE="/tmp/shift-afk.lock"

# Concurrency guard — only one AFK shift at a time
if [[ -f "$LOCKFILE" ]] && kill -0 "$(cat "$LOCKFILE")" 2>/dev/null; then
    echo "shift already running (PID $(cat "$LOCKFILE"))" >&2
    exit 1
fi
echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

for i in $(seq 1 "$MAX_ITERATIONS"); do
    echo "=== shift iteration $i of $MAX_ITERATIONS ==="

    source "$SCRIPT_DIR/_build_prompt.sh"

    result=$(sbx run --name shift-afk claude . "$CTRL_DIR:ro" \
        -- --print \
        --output-format stream-json \
        "$PROMPT" 2>/dev/null | tee /dev/stderr | jq -r 'select(.type == "text") | .content' 2>/dev/null || true)

    if echo "$result" | grep -q '<promise>NO MORE TASKS</promise>'; then
        echo "shift complete after $i iterations"
        exit 0
    fi
done

echo "shift reached max iterations ($MAX_ITERATIONS)"
