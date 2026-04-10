#!/usr/bin/env bash
# _build_prompt.sh — Shared prompt builder for shift scripts.
# Sources into afk.sh / once.sh. Exports $PROMPT and $PROMPT_FILE.
#
# Requires: SCRIPT_DIR set by the caller.

PREVIOUS_COMMITS=$(git log --oneline -5 2>/dev/null || echo "No commits yet")

issues=$(gh issue list --state open --json number,title,body,comments 2>/dev/null || echo "[]")

# Sanitize issue content — escape XML tags that could break prompt structure or inject instructions
issues=$(printf '%s' "$issues" | sed -E \
    -e 's|</?github-issues>|\&lt;github-issues\&gt;|g' \
    -e 's|</?previous-commits>|\&lt;previous-commits\&gt;|g' \
    -e 's|</?system>|\&lt;system\&gt;|g' \
    -e 's|</?instructions>|\&lt;instructions\&gt;|g' \
    -e 's|</?prompt>|\&lt;prompt\&gt;|g' \
    -e 's|</?tool_call>|\&lt;tool_call\&gt;|g' \
    -e 's|</?tool_result>|\&lt;tool_result\&gt;|g')

PROMPT="<github-issues>
$issues
</github-issues>

<previous-commits>
$PREVIOUS_COMMITS
</previous-commits>

$(cat "$SCRIPT_DIR/prompt.md")"

# Write prompt to a temp file to avoid ARG_MAX limits on large backlogs
PROMPT_FILE=$(mktemp /tmp/shift-prompt.XXXXXX)
printf '%s' "$PROMPT" > "$PROMPT_FILE"
