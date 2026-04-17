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
_afk_mode=0

for arg in "$@"; do

    if [[ "$arg" == "--afk" ]]; then
        _afk_mode=1
    fi
done

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

if [[ $_afk_mode -eq 1 ]]; then

    VENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/secrets/.venv"
    _py_bin=""
    if find_python; then
        _py_bin="$PYTHON"
    fi

    echo
    echo "AFK Tool Dependencies:"

    if command -v jq >/dev/null 2>&1; then
        green "  ✓ jq"
    else
        red "  ✗ jq not found — required by shft/afk.sh token parsing"
        _fail=1
    fi

    if command -v sbx >/dev/null 2>&1; then
        green "  ✓ sbx"
    else
        red "  ✗ sbx not found — required by shft/afk.sh sandbox execution"
        _fail=1
    fi

    echo
    echo "AFK GitHub App Credentials (from secrets/.env.secrets):"

    # Check env vars first (loaded via run-with-secrets.sh).
    # If not in env, fall back to checking the .env.secrets file directly.
    _secrets_file="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/secrets/.env.secrets"

    _require_secret() {
        local var="$1" hint="$2"
        local val="${!var:-}"
        if [[ -n "$val" ]]; then
            green "  ✓ $var"
            return 0
        fi
        # Not in env — check .env.secrets file
        if [[ -f "$_secrets_file" ]] && grep -q "^${var}=.\+" "$_secrets_file" 2>/dev/null; then
            green "  ✓ $var (configured in .env.secrets)"
            return 0
        fi
        red "  ✗ $var is not set — $hint"
        _fail=1
        return 1
    }

    _require_secret GITHUB_APP_ID "Required for AFK short-lived token minting"
    _require_secret GITHUB_APP_INSTALLATION_ID "Required for AFK short-lived token minting"
    _require_secret GITHUB_APP_PRIVATE_KEY_B64 "Required for AFK short-lived token minting"

    if [[ -n "${GITHUB_APP_INSTALLATION_ID:-}" ]]; then

        if [[ "$GITHUB_APP_INSTALLATION_ID" =~ ^[0-9]+$ ]]; then
            green "  ✓ GITHUB_APP_INSTALLATION_ID is numeric"
        else
            red "  ✗ GITHUB_APP_INSTALLATION_ID must be numeric (found: $GITHUB_APP_INSTALLATION_ID)"
            _fail=1
        fi
    fi

    if [[ -n "${GITHUB_APP_PRIVATE_KEY_B64:-}" ]]; then

        if [[ -z "$_py_bin" ]]; then
            red "  ✗ Python is required to validate GITHUB_APP_PRIVATE_KEY_B64"
            _fail=1
        elif "$_py_bin" - <<'PY' >/dev/null 2>&1
import base64
import os
import sys

value = os.getenv("GITHUB_APP_PRIVATE_KEY_B64", "")

try:
    base64.b64decode(value, validate=True)
except Exception:
    sys.exit(1)

sys.exit(0)
PY
        then
            green "  ✓ GITHUB_APP_PRIVATE_KEY_B64 decodes successfully"
        else
            red "  ✗ GITHUB_APP_PRIVATE_KEY_B64 is not valid base64"
            _fail=1
        fi
    fi

    if [[ -n "${GITHUB_TOKEN:-}" ]] || [[ -n "${GITHUB_PACKAGE_REGISTRY_TOKEN:-}" ]]; then
        red "  ✗ PAT detected in AFK mode. Remove GITHUB_TOKEN/GITHUB_PACKAGE_REGISTRY_TOKEN and configure GitHub App credentials"
        red "  ✗ See README: 'Exact secure setup after clone (operator quick path)'"
        _fail=1
    else
        green "  ✓ No PAT variables detected for AFK mode"
    fi
fi

# ── Symlink / file checks ────────────────────────────────────────────────────
echo
echo "File System:"

if bash "$HOME/dotfiles/bin/validate-symlinks.sh"; then
    :
else
    _fail=1
fi

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

VENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/secrets/.venv"
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

if [[ $_afk_mode -eq 1 ]]; then
    yellow "  ~ Skipping shell leak checks in --afk mode (validation runs via run-with-secrets)"
else
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

# When sourced (e.g., from bootstrap.sh), return instead of exit so the
# caller can handle the exit code and print its own next-steps.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return $_fail 2>/dev/null || true
fi
exit $_fail
