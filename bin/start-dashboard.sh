#!/usr/bin/env bash
# start-dashboard.sh — start/stop/status wrapper for dashboard-daemon.js

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
WORKING_DIR="$DOTFILES/working"
DAEMON_JS="$DOTFILES/bin/dashboard-daemon.js"
PID_FILE="$WORKING_DIR/dashboard-daemon.pid"
LOG_FILE="$WORKING_DIR/dashboard-daemon.log"
HTTP_PORT="${DASHBOARD_PORT:-7823}"

mkdir -p "$WORKING_DIR"

_is_running() {
    [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

case "${1:-start}" in
    --stop|stop)
        if _is_running; then
            kill "$(cat "$PID_FILE")" 2>/dev/null || true
            rm -f "$PID_FILE"
            green "Dashboard daemon stopped"
        else
            yellow "Dashboard daemon not running"
        fi
        exit 0
        ;;

    --status|status)
        if _is_running; then
            green "Dashboard daemon running (PID $(cat "$PID_FILE"))"
            echo "  http://localhost:$HTTP_PORT/api/state"
            echo "  Log: $LOG_FILE"
        else
            yellow "Dashboard daemon not running"
        fi
        exit 0
        ;;

    --restart|restart)
        bash "$0" --stop >/dev/null 2>&1 || true
        exec bash "$0" start
        ;;

    --fg|foreground)
        if ! command -v node >/dev/null 2>&1; then
            red "Node.js not found"
            exit 1
        fi
        exec node "$DAEMON_JS" --port "$HTTP_PORT"
        ;;
esac

if ! command -v node >/dev/null 2>&1; then
    red "Node.js not found — required for dashboard daemon"
    exit 1
fi

if _is_running; then
    green "Dashboard daemon already running (PID $(cat "$PID_FILE"))"
    echo "  http://localhost:$HTTP_PORT/api/state"
    exit 0
fi

rm -f "$PID_FILE"

nohup node "$DAEMON_JS" --port "$HTTP_PORT" > "$LOG_FILE" 2>&1 < /dev/null &
echo $! > "$PID_FILE"

sleep 0.3
if _is_running; then
    green "Dashboard daemon started (PID $(cat "$PID_FILE"))"
    echo "  http://localhost:$HTTP_PORT/api/state"
    echo "  Log: $LOG_FILE"
else
    red "Dashboard daemon failed to start"
    red "Check: $LOG_FILE"
    exit 1
fi
