#!/usr/bin/env bash
# FAIL_MODE: open
# session-scope-warning.sh — UserPromptSubmit hook: graduated session-length
# warnings based on turn count.
#
# Receives UserPromptSubmit JSON on stdin.
#
# Rationale: context-warning.sh was designed to warn on context-window
# %-used, but that data path depends on an unfinished statusLine bridge
# (hooks/experiments/statusline-probe.sh) and statusLine itself is a Claude
# Code CLI concept with no confirmed GitHub Copilot Chat equivalent. Turn
# count needs no such bridge — it's derivable from this hook firing on every
# prompt — so it works identically in both editors and gives the same
# "wrap up / hand off" signal global.instructions.md already asks for.
#
# This never blocks — UserPromptSubmit hooks that exit non-zero would erase
# the user's prompt from context, which is worse than a missed warning.

set -Eeuo pipefail
trap 'exit 0' ERR  # fail-open: any error → allow

command -v jq &>/dev/null || exit 0

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // .sessionId // "unknown"')

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
STATE_DIR="$DOTFILES/working/runtime/explore-scope"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

# Best-effort prune of stale per-session counters (>24h old). Never fatal.
find "$STATE_DIR" -maxdepth 1 -name '*.turns' -mmin +1440 -delete 2>/dev/null || true

TURNS_FILE="$STATE_DIR/$SESSION_ID.turns"

TURNS=0
if [[ -f "$TURNS_FILE" ]]; then
    TURNS=$(cat "$TURNS_FILE" 2>/dev/null | tr -d '[:space:]')
    [[ "$TURNS" =~ ^[0-9]+$ ]] || TURNS=0
fi
TURNS=$((TURNS + 1))
echo "$TURNS" > "$TURNS_FILE" 2>/dev/null || true

if (( TURNS >= 40 && TURNS % 20 == 0 )); then
    jq -cn --arg msg "🔴 SESSION LENGTH WARNING: ${TURNS} turns in this session. Follow the handoff protocol NOW — commit current work, write remaining plan to working/, and provide a pickup command for a fresh session." \
        '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":$msg}}'
    exit 0
fi

if (( TURNS == 20 )); then
    jq -cn --arg msg "⚠️ SESSION LENGTH: ${TURNS} turns in this session. Start wrapping up this slice — consider committing current work and starting a fresh session soon." \
        '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":$msg}}'
    exit 0
fi

exit 0
