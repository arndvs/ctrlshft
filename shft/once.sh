#!/usr/bin/env bash

# HITL shft — runs Claude once while you watch.
# Usage: ./shft/once.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/_build_prompt.sh"
trap 'rm -f "$PROMPT_FILE"' EXIT

# Inject proxy env vars if enabled
source "$SCRIPT_DIR/_proxy_env.sh" "hitl"

# HUD producer: canonical emitter (ADR-003). Fail-open — HUD problems never block the run.
source "$SCRIPT_DIR/../bin/write-hud-state.sh"

# ANTHROPIC_MODEL is set by _proxy_env.sh when proxying; --model flag not needed.
write_hud_event "info" "HITL once: session started" "" "" "once"
set +e
claude --permission-mode acceptEdits -- "$(cat "$PROMPT_FILE")"
_once_ec=$?
set -e
write_hud_event "info" "HITL once: session finished (exit $_once_ec)" "" "" "once"
exit "$_once_ec"
