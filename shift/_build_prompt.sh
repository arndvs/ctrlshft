#!/usr/bin/env bash
# _build_prompt.sh — Shared prompt builder for shift scripts.
# Sources into afk.sh / once.sh. Exports $PROMPT.
#
# Requires: SCRIPT_DIR set by the caller.

PREVIOUS_COMMITS=$(git log --oneline -5 2>/dev/null || echo "No commits yet")

issues=$(gh issue list --state open --json number,title,body,comments 2>/dev/null || echo "[]")

# Sanitize issue content — escape XML-like closing tags to prevent prompt injection
issues=$(printf '%s' "$issues" | sed 's|</github-issues>|\&lt;/github-issues\&gt;|g; s|</previous-commits>|\&lt;/previous-commits\&gt;|g')

PROMPT="<github-issues>
$issues
</github-issues>

<previous-commits>
$PREVIOUS_COMMITS
</previous-commits>

$(cat "$SCRIPT_DIR/prompt.md")"
