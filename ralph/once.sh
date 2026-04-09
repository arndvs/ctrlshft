#!/bin/bash

# HITL Ralph — runs Claude once while you watch.
# Usage: ./ralph/once.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PREVIOUS_COMMITS=$(git log --oneline -5 2>/dev/null || echo "No commits yet")

issues=$(gh issue list --state open --json number,title,body,comments 2>/dev/null || echo "[]")

prompt="<github-issues>
$issues
</github-issues>

<previous-commits>
$PREVIOUS_COMMITS
</previous-commits>

$(cat "$SCRIPT_DIR/prompt.md")"

claude --permission-mode accept-edits "$prompt"
