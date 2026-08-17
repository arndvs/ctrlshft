#!/usr/bin/env bash
# FAIL_MODE: open
# exploration-scope-guard.sh — PreToolUse hook: nudge toward subagent delegation.
#
# Receives PreToolUse JSON on stdin (matcher: Read|Grep|Glob|Task).
#
# VERIFIED (2026-07-27, raw main.jsonl debug log): GitHub Copilot Chat does
# NOT enforce the settings.json `matcher` field at all — every hook
# registered under an event fires for every tool call regardless of matcher,
# and the `tool_name` in the hook's own stdin JSON is Copilot's *native* tool
# name (read_file, grep_search, file_search, runSubagent), never the Claude
# Code canonical name (Read, Grep, Glob, Task). Every existing Bash-matcher
# hook in this repo survives that because it re-checks tool_input.command
# presence internally. This hook must do the equivalent: match on both
# naming schemes rather than trust the matcher.
#
# Rationale: skills/explore/SKILL.md instructs the agent to delegate deep
# exploration to a dedicated search_subagent instead of reading/grepping files
# one-by-one in the main thread. That's prose the model can forget or
# rationalize past. This hook makes the recommendation mechanical: it counts
# consecutive raw exploration calls per session and injects an escalating
# reminder every 15 calls. Spawning a subagent (Task / runSubagent) resets
# the counter, since delegated exploration no longer taxes the main thread.
#
# This never blocks — it only adds additionalContext. Exploration is
# legitimate work; the goal is a nudge at the point of habit, not a gate.

set -Eeuo pipefail
trap 'exit 0' ERR  # fail-open: any error → allow

command -v jq &>/dev/null || exit 0

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
[[ -n "$TOOL_NAME" ]] || exit 0

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // .sessionId // "unknown"')

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
STATE_DIR="$DOTFILES/working/runtime/explore-scope"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

# Best-effort prune of stale per-session counters (>24h old). Never fatal.
find "$STATE_DIR" -maxdepth 1 -name '*.count' -mmin +1440 -delete 2>/dev/null || true

COUNT_FILE="$STATE_DIR/$SESSION_ID.count"

# Spawning a subagent is the desired behavior — reset the counter.
# (Task = Claude Code's canonical name, runSubagent = Copilot Chat's native name.)
if [[ "$TOOL_NAME" == "Task" || "$TOOL_NAME" == "runSubagent" ]]; then
    echo 0 > "$COUNT_FILE" 2>/dev/null || true
    exit 0
fi

# Match both Claude Code canonical names and Copilot Chat native names —
# the matcher field in settings.json is not enforced by Copilot Chat.
case "$TOOL_NAME" in
    Read|read_file|Grep|grep_search|Glob|file_search) ;;
    *) exit 0 ;;
esac

COUNT=0
if [[ -f "$COUNT_FILE" ]]; then
    COUNT=$(cat "$COUNT_FILE" 2>/dev/null | tr -d '[:space:]')
    [[ "$COUNT" =~ ^[0-9]+$ ]] || COUNT=0
fi
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNT_FILE" 2>/dev/null || true

# Escalating reminder every 15 raw exploration calls without delegation.
if (( COUNT % 15 == 0 )); then
    if (( COUNT >= 30 )); then
        MSG="🔴 ${COUNT} raw exploration calls (Read/Grep/Glob) this session without delegating to a subagent. Spawn a search_subagent per skills/explore/SKILL.md for further exploration instead of continuing to read files directly."
    else
        MSG="⚠️ ${COUNT} raw exploration calls this session. Consider delegating further exploration to a subagent (skills/explore/SKILL.md) instead of reading/grepping one file at a time."
    fi
    jq -cn --arg msg "$MSG" '{"hookSpecificOutput":{"additionalContext":$msg}}' >&2
fi

exit 0
