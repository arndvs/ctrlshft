#!/usr/bin/env bash
# validate-symlinks.sh — Verify consumer paths point back to ~/dotfiles.
#
# On Linux/macOS, consumer paths must be symlinks to dotfiles sources.
# On Windows, fallback copies are allowed, but content must match source.
#
# Exit code: 0 when all checks pass, 1 when any required check fails.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

DOTFILES="$HOME/dotfiles"
CLAUDE_DIR="$HOME/.claude"
COPILOT_DIR="$HOME/.copilot"
AGENTS_DIR="$HOME/.agents"
OS="$(detect_os)"

_fail=0
_warn=0

check_link_or_windows_copy() {
    local source="$1"
    local target="$2"
    local label="$3"

    if [[ -L "$target" ]]; then
        local current
        current="$(readlink "$target")"
        if [[ "$current" == "$source" ]]; then
            green "  ✓ $label symlink is correct"
        else
            red "  ✗ $label points to $current (expected $source)"
            _fail=1
        fi
        return
    fi

    if [[ "$OS" != "windows" ]]; then
        red "  ✗ $label is not a symlink (expected -> $source)"
        _fail=1
        return
    fi

    if [[ ! -e "$target" ]]; then
        red "  ✗ $label is missing"
        _fail=1
        return
    fi

    if [[ -d "$source" && -d "$target" ]]; then
        if diff -qr "$source" "$target" >/dev/null 2>&1; then
            yellow "  ~ $label is a Windows fallback copy (content matches)"
            _warn=1
        else
            red "  ✗ $label fallback copy has drifted from $source"
            _fail=1
        fi
    elif [[ -f "$source" && -f "$target" ]]; then
        if cmp -s "$source" "$target"; then
            yellow "  ~ $label is a Windows fallback copy (content matches)"
            _warn=1
        else
            red "  ✗ $label fallback copy has drifted from $source"
            _fail=1
        fi
    else
        red "  ✗ $label type mismatch (source and target differ in kind)"
        _fail=1
    fi
}

echo "Symlink / Consumer Integrity:"

check_link_or_windows_copy "$DOTFILES/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md" "~/.claude/CLAUDE.md"
check_link_or_windows_copy "$DOTFILES/skills" "$CLAUDE_DIR/skills" "~/.claude/skills"
check_link_or_windows_copy "$DOTFILES/agents" "$CLAUDE_DIR/agents" "~/.claude/agents"
check_link_or_windows_copy "$DOTFILES/rules" "$CLAUDE_DIR/rules" "~/.claude/rules"
check_link_or_windows_copy "$DOTFILES/skills" "$COPILOT_DIR/skills" "~/.copilot/skills"
check_link_or_windows_copy "$DOTFILES/skills" "$AGENTS_DIR/skills" "~/.agents/skills"

if [[ $_fail -eq 0 ]] && [[ $_warn -eq 0 ]]; then
    green "  ✓ Consumer integrity is healthy"
fi

exit $_fail
