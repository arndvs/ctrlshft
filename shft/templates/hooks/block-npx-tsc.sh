#!/bin/bash
set -euo pipefail

# block-npx-tsc.sh — Claude Code hook that intercepts bare `npx tsc` commands
# and redirects to the project's npm script instead.
#
# Install as a PreToolUse hook in .claude/settings.json:
#   { "hooks": { "PreToolUse": [{ "matcher": "Bash", "command": ".sandcastle/hooks/block-npx-tsc.sh" }] } }
#
# Why: `npx tsc` runs from the repo root, ignoring the engine's tsconfig.json
# path. The npm script ensures tsc runs from the correct directory.

if ! command -v jq &>/dev/null; then
  exit 0
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
FIRST_WORD=$(echo "$COMMAND" | awk '{print $1}')

if [[ "$FIRST_WORD" = "npx" ]] && echo "$COMMAND" | head -1 | grep -qE 'npx\s+tsc(\s|$)'; then
  echo 'Use `npm run typecheck` instead of `npx tsc`' >&2
  exit 2
fi
