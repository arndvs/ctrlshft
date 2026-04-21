#!/usr/bin/env bash
# start-hud.sh — Start, stop, or check the ctrl+shft HUD daemon.
#
# Usage:
#   bash ~/dotfiles/bin/start-hud.sh           # start in background
#   bash ~/dotfiles/bin/start-hud.sh --stop    # stop running daemon
#   bash ~/dotfiles/bin/start-hud.sh --status  # check status
#   bash ~/dotfiles/bin/start-hud.sh --restart # restart
#   bash ~/dotfiles/bin/start-hud.sh --fg      # foreground (debug mode)
#
# Follows the same conventions as bootstrap.sh:
#   - Sources _lib.sh for green/yellow/red
#   - Uses mkdir lock (same as afk.sh)
#   - Works on macOS, Linux, WSL, Git Bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
WORKING="$DOTFILES/working"
DAEMON_JS="$DOTFILES/bin/hud-daemon.js"
PID_FILE="$WORKING/hud-daemon.pid"
LOG_FILE="$WORKING/hud-daemon.log"
HTTP_PORT="${HUD_PORT:-7823}"
WS_PORT="${HUD_WS_PORT:-7822}"

mkdir -p "$WORKING"

# ── Helpers ───────────────────────────────────────────────────────────────────
_daemon_running() {
    [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

_open_browser() {
    local url="http://localhost:$HTTP_PORT"
    case "$(detect_os)" in
        macos)   open "$url" ;;
        linux)   xdg-open "$url" 2>/dev/null || true ;;
        windows) start "$url" 2>/dev/null || true ;;
    esac
}

_wait_for_daemon() {
    local attempts=0
    while [[ $attempts -lt 20 ]]; do
        if curl -sf --max-time 1 "http://localhost:$HTTP_PORT/api/state" > /dev/null 2>&1; then
            return 0
        fi
        sleep 0.3
        attempts=$(( attempts + 1 ))
    done
    return 1
}

# ── Commands ──────────────────────────────────────────────────────────────────
case "${1:-start}" in

    --stop|stop)
        if _daemon_running; then
            kill "$(cat "$PID_FILE")"
            rm -f "$PID_FILE"
            green "HUD daemon stopped"
        else
            yellow "HUD daemon not running"
        fi
        exit 0
        ;;

    --status|status)
        if _daemon_running; then
            green "HUD daemon running (PID $(cat "$PID_FILE"))"
            echo "  http://localhost:$HTTP_PORT"
            echo "  ws://localhost:$WS_PORT"
            echo "  Log: $LOG_FILE"
        else
            yellow "HUD daemon not running"
            echo "  Start with: bash ~/dotfiles/bin/start-hud.sh"
        fi
        exit 0
        ;;

    --restart|restart)
        bash "$0" --stop 2>/dev/null || true
        sleep 0.5
        exec bash "$0" start
        ;;

    --fg|foreground)
        green "Starting HUD in foreground..."
        node "$DAEMON_JS" --port "$HTTP_PORT" --ws-port "$WS_PORT" --debug
        exit 0
        ;;

esac

# ── Start ─────────────────────────────────────────────────────────────────────

# Already running?
if _daemon_running; then
    green "HUD already running (PID $(cat "$PID_FILE"))"
    echo "  http://localhost:$HTTP_PORT"
    _open_browser
    exit 0
fi

# Stale PID?
rm -f "$PID_FILE"

# Node.js check
if ! command -v node &>/dev/null; then
    red "Node.js not found — required for the HUD daemon"
    red "Install from: https://nodejs.org (v18+)"
    exit 1
fi

_node_major=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1)
if [[ "${_node_major:-0}" -lt 18 ]]; then
    yellow "Node.js 18+ recommended (found: $(node --version))"
    yellow "HUD may work but is untested on older versions"
fi

# SQLite check (optional but recommended)
if ! node -e "require('better-sqlite3')" 2>/dev/null; then
    yellow "better-sqlite3 not installed — compliance history will not persist across restarts"
    yellow "Install: cd ~/dotfiles && npm install better-sqlite3"
fi

echo ""
green "Starting ctrl+shft HUD daemon..."

nohup node "$DAEMON_JS" \
    --port "$HTTP_PORT" \
    --ws-port "$WS_PORT" \
    >> "$LOG_FILE" 2>&1 &

echo $! > "$PID_FILE"

if _wait_for_daemon; then
    green "HUD running (PID $(cat "$PID_FILE"))"
    echo ""
    echo "  HUD  →  http://localhost:$HTTP_PORT"
    echo "  WebSocket  →  ws://localhost:$WS_PORT"
    echo "  Log        →  $LOG_FILE"
    echo ""
    _open_browser
else
    red "HUD failed to start"
    red "Check log: $LOG_FILE"
    cat "$LOG_FILE" | tail -20
    rm -f "$PID_FILE"
    exit 1
fi
