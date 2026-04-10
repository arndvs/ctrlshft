#!/usr/bin/env bash
# _lib.sh — Shared utilities for bin/ scripts.
#
# Source this file from other scripts:
#   source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
#
# Provides: green, yellow, red, detect_os, find_python, find_venv_python
#
# NOTE: load-secrets.sh intentionally does NOT source this file because
# it's loaded from .bashrc/.zshrc and must remain self-contained.

# ── Colors ────────────────────────────────────────────────────────────────────
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
red()    { printf '\033[31m%s\033[0m\n' "$*"; }

# ── OS detection ──────────────────────────────────────────────────────────────
# Returns: "windows", "linux", "macos", or "unknown"
detect_os() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        Linux*)               echo "linux"   ;;
        Darwin*)              echo "macos"   ;;
        *)                    echo "unknown" ;;
    esac
}

# ── Python discovery ──────────────────────────────────────────────────────────
# Sets PYTHON to the best available Python binary (venv first, then system).
# Requires VENV_DIR to be set. Returns 1 if no Python found.
find_python() {
    PYTHON=""
    if [[ -f "$VENV_DIR/Scripts/python.exe" ]]; then
        PYTHON="$VENV_DIR/Scripts/python.exe"
    elif [[ -f "$VENV_DIR/bin/python" ]]; then
        PYTHON="$VENV_DIR/bin/python"
    else
        local cmd
        for cmd in python3 python; do
            if "$cmd" --version &>/dev/null; then
                PYTHON="$cmd"
                break
            fi
        done
    fi
    [[ -n "$PYTHON" ]]
}

# ── Venv Python lookup ────────────────────────────────────────────────────────
# Sets _venv_python to the venv's Python binary path, or empty if not found.
# Requires VENV_DIR to be set.
find_venv_python() {
    _venv_python=""
    if [[ -f "$VENV_DIR/Scripts/python.exe" ]]; then
        _venv_python="$VENV_DIR/Scripts/python.exe"
    elif [[ -f "$VENV_DIR/bin/python" ]]; then
        _venv_python="$VENV_DIR/bin/python"
    fi
}
