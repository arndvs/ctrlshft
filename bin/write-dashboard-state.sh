#!/usr/bin/env bash
# write-dashboard-state.sh — Non-blocking dashboard event emitter.
#
# Usage:
#   bash ~/dotfiles/bin/write-dashboard-state.sh context "Active contexts: general,nextjs"
#   bash ~/dotfiles/bin/write-dashboard-state.sh info "Task started"
#
# Transport priority:
#   1) named pipe    ~/dotfiles/working/dashboard.pipe
#   2) HTTP fallback http://localhost:${DASHBOARD_PORT:-7823}/api/event
#   3) JSONL append  ~/dotfiles/working/events.jsonl

set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
WORKING_DIR="$DOTFILES/working"
PIPE_PATH="$WORKING_DIR/dashboard.pipe"
JSONL_PATH="$WORKING_DIR/events.jsonl"
HTTP_PORT="${DASHBOARD_PORT:-7823}"

_json_escape() {
    local s="$1"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/ }
    s=${s//$'\r'/ }
    printf '%s' "$s"
}

write_dashboard_event() {
    local type="${1:-info}"
    local message="${2:-}"
    local project project_path contexts timestamp time_display safe_message payload

    project=$(basename "${PWD:-.}" 2>/dev/null || echo "unknown")
    project_path="${PWD/$HOME/~}"
    contexts="${ACTIVE_CONTEXTS:-general}"
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")
    time_display=$(date +"%H:%M:%S" 2>/dev/null || echo "")
    safe_message=$(_json_escape "$message")

    payload=$(printf '{"type":"%s","project":"%s","projectPath":"%s","contexts":"%s","message":"%s","timestamp":"%s","time":"%s"}' \
        "$type" "$project" "$project_path" "$contexts" "$safe_message" "$timestamp" "$time_display")

    if [[ -p "$PIPE_PATH" ]]; then
        ( printf '%s\n' "$payload" > "$PIPE_PATH" ) 2>/dev/null &
        return 0
    fi

    if command -v curl >/dev/null 2>&1; then
        if curl -sf --max-time 0.3 \
            "http://localhost:${HTTP_PORT}/api/event" \
            -X POST -H "Content-Type: application/json" \
            -d "$payload" >/dev/null 2>&1; then
            return 0
        fi
    fi

    mkdir -p "$WORKING_DIR" 2>/dev/null || true
    printf '%s\n' "$payload" >> "$JSONL_PATH" 2>/dev/null || true
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    write_dashboard_event "${1:-info}" "${2:-}"
fi
