#!/usr/bin/env bash

# HITL shift — runs Claude once while you watch.
# Usage: ./shift/once.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/_build_prompt.sh"

claude --permission-mode accept-edits "$(cat "$PROMPT_FILE")"
rm -f "$PROMPT_FILE"
