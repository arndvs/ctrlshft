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
echo "Core Variables:"
_require PYTHONUTF8 "Should be 1 — set in secrets/.env"
_require GITHUB_USERNAME "Set in secrets/.env"
_recommend GITHUB_PACKAGE_REGISTRY_TOKEN "Needed for package publishing"
_recommend OPENAI_API_KEY "Needed for AI skills"
_recommend GCP_CREDENTIALS_FILE "Needed for Google API scripts"

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

if [[ -f "$HOME/dotfiles/secrets/.env" ]]; then
    green "  ✓ secrets/.env exists"
else
    red "  ✗ secrets/.env missing — run: cp ~/dotfiles/.env.example ~/dotfiles/secrets/.env"
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

# ── Citation-specific vars (only with --all) ──────────────────────────────────
if $CHECK_ALL; then
    echo
    echo "Citation Builder Variables:"
    _require CITATION_VAULT_KEY "AES-256 vault key — generate with: python -c \"from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())\""
    _require CITATION_EMAIL "IMAP email for verification polling"
    _require CITATION_EMAIL_PASSWORD "IMAP password"
    _recommend CITATION_IMAP_HOST "Defaults to imap.gmail.com if unset"
    _require CITATION_VERIFICATION_EMAIL "Email for directory registrations"
    _recommend CITATION_BUSINESS_EMAIL "Business email for high-priority directories"
    _require CITATION_SPREADSHEET_ID "Google Sheet ID for campaign tracking"

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
