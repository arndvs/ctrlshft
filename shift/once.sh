#!/usr/bin/env bash

# HITL shift — runs Claude once while you watch.
# Usage: ./shift/once.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PREVIOUS_COMMITS=$(git log --oneline -5 2>/dev/null || echo "No commits yet")

issues=$(gh issue list --state open --json number,title,body,comments 2>/dev/null || echo "[]")

# Sanitize issue content — escape XML-like closing tags to prevent prompt injection
issues=$(printf '%s' "$issues" | sed 's|</github-issues>|\&lt;/github-issues\&gt;|g; s|</previous-commits>|\&lt;/previous-commits\&gt;|g')

prompt="<github-issues>
$issues
</github-issues>

<previous-commits>
$PREVIOUS_COMMITS
</previous-commits>

$(cat "$SCRIPT_DIR/prompt.md")"

claude --permission-mode accept-edits "$prompt"
