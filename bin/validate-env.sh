#!/usr/bin/env bash
# validate-env.sh — Validate environment variables and hardening posture.
#
# Checks: required env vars, file system (symlinks, secrets files, venv),
# shell integration, and hardening (secrets not leaked into shell, deny rules).
#
# Usage:
#   bash ~/dotfiles/bin/validate-env.sh
#
# Exit code: 0 if all required checks pass, 1 if any fail.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

_fail=0
_warn=0

_require() {
    local var="$1"
    local hint="${2:-}"
    local val="${!var:-}"
    if [[ -z "$val" ]]; then
        red "  ✗ $var is not set${hint:+ — $hint}"
        _fail=1
    else
        green "  ✓ $var"
    fi
}

_recommend() {
    local var="$1"
    local hint="${2:-}"
    local val="${!var:-}"
    if [[ -z "$val" ]]; then
        yellow "  ~ $var is not set${hint:+ — $hint}"
        _warn=1
    else
        green "  ✓ $var"
    fi
}

echo "================================================"
echo "Dotfiles Environment Variable Validation"
echo "================================================"

# ── Core vars (always checked) ────────────────────────────────────────────────
echo
echo "Core Variables (from secrets/.env.agent):"
_require PYTHONUTF8 "Should be 1 — set in secrets/.env.agent"
_require GITHUB_USERNAME "Set in secrets/.env.agent"
_recommend GCP_CREDENTIALS_FILE "Needed for Google API scripts — set in secrets/.env.agent"

# ── Symlink / file checks ────────────────────────────────────────────────────
echo
echo "File System:"

if [[ -f "$HOME/.claude/CLAUDE.md" ]]; then
    green "  ✓ ~/.claude/CLAUDE.md exists"
else
    red "  ✗ ~/.claude/CLAUDE.md missing — run: bash ~/dotfiles/bin/bootstrap.sh"
    _fail=1
fi

if [[ -d "$HOME/.claude/skills" ]]; then
    green "  ✓ ~/.claude/skills exists"
else
    red "  ✗ ~/.claude/skills missing — run: bash ~/dotfiles/bin/bootstrap.sh"
    _fail=1
fi

if [[ -f "$HOME/dotfiles/secrets/.env.agent" ]]; then
    green "  ✓ secrets/.env.agent exists"
else
    if [[ -f "$HOME/dotfiles/secrets/.env" ]]; then
        yellow "  ~ secrets/.env exists (legacy) — migrate to .env.agent + .env.secrets"
        _warn=1
    else
        red "  ✗ secrets/.env.agent missing — run: cp ~/dotfiles/.env.agent.example ~/dotfiles/secrets/.env.agent"
        _fail=1
    fi
fi

if [[ -f "$HOME/dotfiles/secrets/.env.secrets" ]]; then
    green "  ✓ secrets/.env.secrets exists"
else
    red "  ✗ secrets/.env.secrets missing — run: cp ~/dotfiles/.env.secrets.example ~/dotfiles/secrets/.env.secrets"
    _fail=1
fi

VENV_DIR="$HOME/dotfiles/secrets/.venv"
if [[ -d "$VENV_DIR" ]]; then
    find_venv_python
    if [[ -n "$_venv_python" ]] && "$_venv_python" --version &>/dev/null; then
        green "  ✓ Python venv functional"
    else
        red "  ✗ Python venv exists but broken — fix: rm -rf $VENV_DIR && bash ~/dotfiles/bin/bootstrap.sh"
        _fail=1
    fi
else
    yellow "  ~ Python venv not found (optional — needed for Google API and citation scripts)"
    _warn=1
fi

# ── Shell integration ─────────────────────────────────────────────────────────
echo
echo "Shell Integration:"

if [[ -f "$HOME/.bashrc" ]]; then
    if grep -qF "load-secrets.sh" "$HOME/.bashrc"; then
        green "  ✓ .bashrc has load-secrets"
    else
        red "  ✗ .bashrc missing load-secrets — run: bash ~/dotfiles/bin/bootstrap.sh"
        _fail=1
    fi
else
    yellow "  ~ .bashrc not found (expected on zsh-only systems)"
fi

if [[ -f "$HOME/.zshrc" ]]; then
    if grep -qF "load-secrets.sh" "$HOME/.zshrc"; then
        green "  ✓ .zshrc has load-secrets"
    else
        yellow "  ~ .zshrc exists but missing load-secrets — run: bash ~/dotfiles/bin/bootstrap.sh"
        _warn=1
    fi
fi
# ── Hardening checks ─────────────────────────────────────────────────────────
echo
echo "Environment Hardening:"

# Secrets should NOT be in shell environment — hard failure if leaked
if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    red "  ✗ OPENAI_API_KEY is in shell env — should only be in .env.secrets (process-scoped)"
    _fail=1
else
    green "  ✓ OPENAI_API_KEY not in shell env (good — process-scoped only)"
fi

if [[ -n "${GITHUB_PACKAGE_REGISTRY_TOKEN:-}" ]]; then
    red "  ✗ GITHUB_PACKAGE_REGISTRY_TOKEN is in shell env — should only be in .env.secrets"
    _fail=1
else
    green "  ✓ GITHUB_PACKAGE_REGISTRY_TOKEN not in shell env (good)"
fi

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    red "  ✗ GITHUB_TOKEN is in shell env — should only be in .env.secrets"
    _fail=1
else
    green "  ✓ GITHUB_TOKEN not in shell env (good)"
fi

if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    red "  ✗ ANTHROPIC_API_KEY is in shell env — should only be in .env.secrets"
    _fail=1
else
    green "  ✓ ANTHROPIC_API_KEY not in shell env (good)"
fi

if [[ -f "$HOME/.claude/settings.json" ]] && grep -q '"deny"' "$HOME/.claude/settings.json" 2>/dev/null; then
    green "  ✓ Claude Code deny rules configured"
else
    yellow "  ~ Claude Code deny rules not found — recommended for agent hardening"
    _warn=1
fi
# ── Summary ───────────────────────────────────────────────────────────────────
echo
echo "================================================"
if [[ $_fail -eq 0 ]] && [[ $_warn -eq 0 ]]; then
    green "All checks passed!"
elif [[ $_fail -eq 0 ]]; then
    yellow "Passed with warnings (non-blocking)."
else
    red "Some checks FAILED — review errors above."
fi

exit $_fail
