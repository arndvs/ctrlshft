#!/usr/bin/env bash
# block-npx-tsc.sh — Pre-commit hook to prevent `npx tsc` in CI
#
# Agents sometimes run `npx tsc` instead of `npx tsc --noEmit`, which
# emits compiled JS files into the working tree. This hook blocks that.
#
# Install: copy to .git/hooks/pre-commit or add to your hook manager.

set -euo pipefail

# Check staged files for compiled JS that shouldn't be there
COMPILED_JS=$(git diff --cached --name-only --diff-filter=A | grep -E '\.(js|jsx)$' | grep -v 'node_modules/' | grep -v '.sandcastle/' || true)

if [ -n "$COMPILED_JS" ]; then
  # Check if these look like tsc output (have corresponding .ts files)
  SUSPICIOUS=""
  while IFS= read -r jsfile; do
    tsfile="${jsfile%.js}.ts"
    tsxfile="${jsfile%.jsx}.tsx"
    if [ -f "$tsfile" ] || [ -f "$tsxfile" ]; then
      SUSPICIOUS="$SUSPICIOUS\n  $jsfile"
    fi
  done <<< "$COMPILED_JS"

  if [ -n "$SUSPICIOUS" ]; then
    echo "Blocked: staged JS files that appear to be tsc output:" >&2
    echo -e "$SUSPICIOUS" >&2
    echo "" >&2
    echo "Did you run 'npx tsc' without --noEmit? Remove these files:" >&2
    echo "  git reset HEAD \$(git diff --cached --name-only --diff-filter=A | grep -E '\\.(js|jsx)$')" >&2
    echo "  git checkout -- \$(git diff --cached --name-only --diff-filter=A | grep -E '\\.(js|jsx)$')" >&2
    exit 1
  fi
fi
