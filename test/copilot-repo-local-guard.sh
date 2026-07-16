#!/usr/bin/env bash
# test/copilot-repo-local-guard.sh — Static guard: repo-local Copilot instructions must not exist.
#
# Copilot instructions for this repo are deployed from the generated CLAUDE.md
# by bootstrap (bin/bootstrap.sh). A root .github/copilot-instructions.md would
# shadow that mechanism and cause drift. This guard fails the test suite if one
# is ever committed.
#
# Template or documentation paths (e.g. shft/templates/, docs/) are NOT blocked
# — only the repo-local load path that Copilot actually reads.
#
# Usage: bash test/copilot-repo-local-guard.sh

set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$(dirname "$0")/..")"

echo
echo "Copilot repo-local instruction guard"
echo "════════════════════════════════════════════════"

BLOCKED_PATH=".github/copilot-instructions.md"

if [[ -f "$BLOCKED_PATH" ]]; then
    printf '  \033[31m✗\033[0m %s exists\n' "$BLOCKED_PATH"
    echo
    echo "  Copilot instructions are deployed from generated CLAUDE.md by bootstrap."
    echo "  Do not add a repo-local .github/copilot-instructions.md — it shadows the"
    echo "  bootstrap-managed symlink and causes instruction drift."
    echo
    echo "  To update Copilot instructions, edit the source rules and re-run bootstrap."
    echo
    exit 1
fi

printf '  \033[32m✓\033[0m no repo-local %s (instructions come from bootstrap)\n' "$BLOCKED_PATH"
echo
exit 0
