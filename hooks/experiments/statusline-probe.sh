#!/usr/bin/env bash
# statusline-probe.sh — Experiment to discover statusLine input format
#
# PURPOSE: Determine how context_window.used_percentage is delivered
# to a statusLine command (stdin JSON, env var, or argument).
#
# The env vars docs confirm the field exists:
#   CLAUDE_AUTOCOMPACT_PCT_OVERRIDE: "This percentage aligns with the
#   context_window.used_percentage field available in status line"
#
# But the delivery mechanism (stdin, env, arg) is undocumented.
#
# SETUP:
#   1. Add to ~/.claude/settings.json:
#      "statusLine": {"type": "command", "command": "bash ~/.claude/hooks/experiments/statusline-probe.sh"}
#
#      If that doesn't work, try the bare string form:
#      "statusLine": "bash ~/.claude/hooks/experiments/statusline-probe.sh"
#
#   2. Start a Claude Code session and do some work (read files, run commands)
#   3. Read the log:  cat ~/.claude/experiments/statusline-probe.log
#   4. Look for used_percentage in stdin, args, or env sections
#   5. Remove the statusLine entry from settings.json when done
#
# DO NOT leave this in production — it writes to disk on every status update.

set -euo pipefail

LOGDIR="$HOME/.claude/experiments"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/statusline-probe.log"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

{
    echo "=== $TIMESTAMP ==="

    echo "--- STDIN ---"
    # Read stdin with a short timeout — statusLine may not send stdin
    # Uses read -t instead of timeout (which requires coreutils on macOS)
    if read -t 0.1 -r STDIN_LINE 2>/dev/null; then
        echo "$STDIN_LINE"
        cat 2>/dev/null || true
    else
        echo "(empty — no stdin within 0.1s)"
    fi

    echo "--- ARGS ($#) ---"
    if [[ $# -gt 0 ]]; then
        for i in "$@"; do echo "  arg: $i"; done
    else
        echo "  (none)"
    fi

    echo "--- ENV (context/token/usage/window/percent/compact) ---"
    env | grep -iE "context|token|usage|percent|compact|window|statusline" || echo "  (none matching)"

    echo "--- ALL ENV (sorted) ---"
    env | sort

    echo ""
} >> "$LOGFILE" 2>&1

# statusLine must print a status string to stdout
echo "probe active"
