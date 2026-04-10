#!/usr/bin/env bash

# HITL shift — runs Claude once while you watch.
# Usage: ./shift/once.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/_build_prompt.sh"
trap 'rm -f "$PROMPT_FILE"' EXIT

cat "$PROMPT_FILE" | claude --permission-mode accept-edits
