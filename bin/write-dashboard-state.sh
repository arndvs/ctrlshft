#!/usr/bin/env bash
# write-dashboard-state.sh — Non-blocking dashboard event emitter.
#
# Usage:
#   bash ~/dotfiles/bin/write-dashboard-state.sh context "Active contexts: general,nextjs"
#   bash ~/dotfiles/bin/write-dashboard-state.sh info "Task started"
#   bash ~/dotfiles/bin/write-dashboard-state.sh compliance pass 5 0 1 '[]'
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

write_compliance_event() {
    local verdict="${1:-pass}"
    local pass_count="${2:-0}"
    local fail_count="${3:-0}"
    local warn_count="${4:-0}"
    local violations_json="${5:-[]}"
    local project project_path contexts timestamp time_display safe_violations payload

    project=$(basename "${PWD:-.}" 2>/dev/null || echo "unknown")
    project_path="${PWD/$HOME/~}"
    contexts="${ACTIVE_CONTEXTS:-general}"
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")
    time_display=$(date +"%H:%M:%S" 2>/dev/null || echo "")
    safe_violations=$(_json_escape "$violations_json")

    payload=$(printf '{"type":"compliance-result","project":"%s","projectPath":"%s","contexts":"%s","message":"Compliance audit: %s PASS, %s FAIL, %s WARN — %s","verdict":"%s","passCount":%s,"failCount":%s,"warnCount":%s,"violations":"%s","timestamp":"%s","time":"%s"}' \
        "$project" "$project_path" "$contexts" \
        "$pass_count" "$fail_count" "$warn_count" "$verdict" \
        "$verdict" "$pass_count" "$fail_count" "$warn_count" \
        "$safe_violations" "$timestamp" "$time_display")

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
    if [[ "${1:-}" == "compliance" ]]; then
        write_compliance_event "${2:-pass}" "${3:-0}" "${4:-0}" "${5:-0}" "${6:-[]}"
    else
        write_dashboard_event "${1:-info}" "${2:-}"
    fi
fi
