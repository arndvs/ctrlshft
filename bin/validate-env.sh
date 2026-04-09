#!/usr/bin/env bash
# validate-env.sh — Validate all prerequisite environment variables are set.
#
# Usage:
#   bash ~/dotfiles/bin/validate-env.sh          # check core vars only
#   bash ~/dotfiles/bin/validate-env.sh --all    # check core + citation vars
#
# Exit code: 0 if all required vars pass, 1 if any are missing.

set -euo pipefail

green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
red()    { printf '\033[31m%s\033[0m\n' "$*"; }

CHECK_ALL=false
for arg in "$@"; do
    [[ "$arg" == "--all" ]] && CHECK_ALL=true
done

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
    _venv_python=""
    [[ -f "$VENV_DIR/Scripts/python.exe" ]] && _venv_python="$VENV_DIR/Scripts/python.exe"
    [[ -f "$VENV_DIR/bin/python" ]] && _venv_python="$VENV_DIR/bin/python"
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

if [[ -f "$HOME/.bashrc" ]] && grep -qF "load-secrets.sh" "$HOME/.bashrc"; then
    green "  ✓ .bashrc has load-secrets"
else
    red "  ✗ .bashrc missing load-secrets — run: bash ~/dotfiles/bin/bootstrap.sh"
    _fail=1
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

if [[ -n "${CITATION_VAULT_KEY:-}" ]]; then
    red "  ✗ CITATION_VAULT_KEY is in shell env — should only be in .env.secrets"
    _fail=1
else
    green "  ✓ CITATION_VAULT_KEY not in shell env (good)"
fi

if [[ -n "${CITATION_EMAIL_PASSWORD:-}" ]]; then
    red "  ✗ CITATION_EMAIL_PASSWORD is in shell env — should only be in .env.secrets"
    _fail=1
else
    green "  ✓ CITATION_EMAIL_PASSWORD not in shell env (good)"
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

if [[ -n "${SANITY_TOKEN:-}" ]]; then
    red "  ✗ SANITY_TOKEN is in shell env — should only be in .env.secrets"
    _fail=1
else
    green "  ✓ SANITY_TOKEN not in shell env (good)"
fi

if [[ -f "$HOME/.claude/settings.json" ]] && grep -q '"deny"' "$HOME/.claude/settings.json" 2>/dev/null; then
    green "  ✓ Claude Code deny rules configured"
else
    yellow "  ~ Claude Code deny rules not found — recommended for agent hardening"
    _warn=1
fi
# ── Citation-specific vars (only with --all) ──────────────────────────────────
if $CHECK_ALL; then
    echo
    echo "Citation Builder Variables (from secrets/.env.agent):"
    _require CITATION_EMAIL "IMAP email for verification polling — set in secrets/.env.agent"
    _recommend CITATION_IMAP_HOST "Defaults to imap.gmail.com if unset"
    _require CITATION_VERIFICATION_EMAIL "Email for directory registrations — set in secrets/.env.agent"
    _recommend CITATION_BUSINESS_EMAIL "Business email for high-priority directories"
    _require CITATION_SPREADSHEET_ID "Google Sheet ID for campaign tracking — set in secrets/.env.agent"

    echo
    echo "Citation Secrets (checked in .env.secrets file — not loaded into shell):"
    _SECRETS_FILE="$HOME/dotfiles/secrets/.env.secrets"
    if [[ ! -f "$_SECRETS_FILE" ]]; then
        red "  ✗ secrets/.env.secrets not found — run: cp ~/dotfiles/.env.secrets.example ~/dotfiles/secrets/.env.secrets"
        _fail=1
    else
        for _svar in CITATION_VAULT_KEY CITATION_EMAIL_PASSWORD; do
            if grep -q "^${_svar}=.\+" "$_SECRETS_FILE" 2>/dev/null; then
                green "  ✓ $_svar defined in .env.secrets"
            else
                red "  ✗ $_svar missing or empty in .env.secrets"
                _fail=1
            fi
        done
    fi

    echo
    echo "Citation Files:"
    if [[ -f "$HOME/dotfiles/skills/citation-builder-skill/config.json" ]]; then
        green "  ✓ citation config.json exists"
    else
        red "  ✗ citation config.json missing — run: cp config.example.json config.json"
        _fail=1
    fi
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
