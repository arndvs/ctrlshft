#!/bin/bash

# AFK Ralph — autonomous loop consuming GitHub issues backlog.
# Usage: ./ralph/afk.sh [max_iterations]
# Default: 5 iterations

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAX_ITERATIONS="${1:-5}"

for i in $(seq 1 "$MAX_ITERATIONS"); do
    echo "=== Ralph iteration $i of $MAX_ITERATIONS ==="

    PREVIOUS_COMMITS=$(git log --oneline -5 2>/dev/null || echo "No commits yet")

    issues=$(gh issue list --state open --json number,title,body,comments 2>/dev/null || echo "[]")

    prompt="<github-issues>
$issues
</github-issues>

<previous-commits>
$PREVIOUS_COMMITS
</previous-commits>

$(cat "$SCRIPT_DIR/prompt.md")"

    result=$(docker sandbox run claude . \
        --print \
        --output-format stream-json \
        "$prompt" 2>&1 | tee /dev/stderr | jq -r 'select(.type == "text") | .content' 2>/dev/null || true)

    if echo "$result" | grep -q '<promise>NO MORE TASKS</promise>'; then
        echo "Ralph complete after $i iterations"
        exit 0
    fi
done

echo "Ralph reached max iterations ($MAX_ITERATIONS)"
