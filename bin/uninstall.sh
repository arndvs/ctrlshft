#!/usr/bin/env bash
# uninstall.sh — Safely remove ctrl+shft symlinks and shell integration.
#
# Usage:
#   bash ~/dotfiles/bin/uninstall.sh
#
# Does not remove ~/dotfiles or delete secrets files.

set -euo pipefail

DOTFILES="$HOME/dotfiles"
CLAUDE_DIR="$HOME/.claude"
COPILOT_DIR="$HOME/.copilot"
AGENTS_DIR="$HOME/.agents"

red()    { printf '\033[0;31m  %s\033[0m\n' "$*"; }
green()  { printf '\033[0;32m  %s\033[0m\n' "$*"; }
yellow() { printf '\033[0;33m  %s\033[0m\n' "$*"; }

_remove_symlink() {
    local link="$1"
    local label="$2"
    if [[ -L "$link" ]]; then
        _target=$(readlink "$link")
        if [[ "$_target" == "$DOTFILES"* ]]; then
            unlink "$link"
            green "Removed symlink: $link -> $_target"
        else
            yellow "Skipping $label — symlink points elsewhere: $_target"
        fi
    elif [[ -e "$link" ]]; then
        yellow "Skipping $label — exists but is not a symlink (manual check needed)"
    else
        yellow "Skipping $label — not found (already removed?)"
    fi
}

echo
green "[1/4] Removing managed symlinks"
_remove_symlink "$CLAUDE_DIR/CLAUDE.md" "~/.claude/CLAUDE.md"
_remove_symlink "$CLAUDE_DIR/skills" "~/.claude/skills"
_remove_symlink "$CLAUDE_DIR/agents" "~/.claude/agents"
_remove_symlink "$CLAUDE_DIR/rules" "~/.claude/rules"
_remove_symlink "$CLAUDE_DIR/commands" "~/.claude/commands"
_remove_symlink "$CLAUDE_DIR/hooks" "~/.claude/hooks"
_remove_symlink "$COPILOT_DIR/skills" "~/.copilot/skills"
_remove_symlink "$AGENTS_DIR/skills" "~/.agents/skills"
_remove_symlink "$HOME/.local/bin/ctrl" "~/.local/bin/ctrl"
_remove_symlink "$HOME/.local/bin/shft" "~/.local/bin/shft"

echo
green "[2/4] Removing shell integration"

_MARKER_BEGIN="# ── dotfiles/load-secrets ──"
_MARKER_END="# ── dotfiles/load-secrets:end ──"

_strip_shell_rc() {
    local rc_file="$1"
    local rc_name="$2"

    if [[ ! -f "$rc_file" ]]; then
        yellow "$rc_name not found — skipping"
        return
    fi

    if ! grep -qF "$_MARKER_BEGIN" "$rc_file"; then
        yellow "$rc_name — ctrl+shft snippet not found (already removed?)"
        return
    fi

    awk -v begin="$_MARKER_BEGIN" -v end="$_MARKER_END" '
        $0 == begin { skip=1; next }
        skip && $0 == end { skip=0; next }
        !skip { print }
    ' "$rc_file" > "$rc_file.ctrlshft.bak" && mv "$rc_file.ctrlshft.bak" "$rc_file"

    green "Removed ctrl+shft snippet from $rc_name"
}

_strip_shell_rc "$HOME/.bashrc" "~/.bashrc"
_strip_shell_rc "$HOME/.zshrc" "~/.zshrc"

echo
green "[3/4] Removing supply-chain guard entries"

if [[ -f "$HOME/.npmrc" ]] && grep -qF "min-release-age" "$HOME/.npmrc"; then
    sed '/^min-release-age=/d' "$HOME/.npmrc" > "$HOME/.npmrc.ctrlshft.bak" && mv "$HOME/.npmrc.ctrlshft.bak" "$HOME/.npmrc"
    green "Removed min-release-age from ~/.npmrc"
else
    yellow "~/.npmrc — entry not found (already removed?)"
fi

UV_CONFIG="$HOME/.config/uv/uv.toml"
if [[ -f "$UV_CONFIG" ]] && grep -qF "exclude-newer" "$UV_CONFIG"; then
    sed '/^exclude-newer =/d' "$UV_CONFIG" > "$UV_CONFIG.ctrlshft.bak" && mv "$UV_CONFIG.ctrlshft.bak" "$UV_CONFIG"
    green "Removed exclude-newer from ~/.config/uv/uv.toml"
else
    yellow "~/.config/uv/uv.toml — entry not found (already removed?)"
fi

echo
green "[4/4] Done"
echo ""
echo "  ctrl+shft has been unlinked from your environment."
echo "  Your ~/dotfiles folder and secrets are untouched."
echo ""
echo "  To finish:"
echo "    1. Reload shell:  source ~/.bashrc  (or ~/.zshrc)"
echo "    2. Verify:        ls ~/.claude/"
