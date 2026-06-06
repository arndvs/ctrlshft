#!/usr/bin/env bash
# check-file-tokens.sh — Verify all template placeholders have been replaced
#
# Scans vendored .sandcastle/ files for unreplaced {{PLACEHOLDER}} tokens.
# Run after init-sandcastle or update-sandcastle to catch missed substitutions.

set -euo pipefail

TARGET_DIR="${1:-.sandcastle}"

if [ ! -d "$TARGET_DIR" ]; then
  echo "Error: directory '$TARGET_DIR' does not exist" >&2
  exit 1
fi

FOUND=0

while IFS= read -r -d '' file; do
  # Skip binary files and node_modules
  case "$file" in
    */node_modules/*) continue ;;
    *.png|*.jpg|*.gif|*.ico|*.woff|*.woff2|*.ttf|*.eot) continue ;;
  esac

  MATCHES=$(grep -nE '\{\{[A-Z_]+\}\}' "$file" 2>/dev/null || true)
  if [ -n "$MATCHES" ]; then
    echo "Unreplaced tokens in $file:"
    echo "$MATCHES" | sed 's/^/  /'
    FOUND=1
  fi
done < <(find "$TARGET_DIR" -type f -print0)

if [ "$FOUND" -eq 0 ]; then
  echo "All template tokens replaced."
  exit 0
else
  echo ""
  echo "Found unreplaced template tokens. Run 'ctrl update-sandcastle' to fix."
  exit 1
fi
