#!/usr/bin/env bash
# load-secrets.sh — Source AGENT-SAFE config into the current shell.
#
# Only loads secrets/.env.agent (non-sensitive config like usernames, hosts, flags).
# Actual secrets (API keys, tokens, passwords) live in secrets/.env.secrets and are
# NEVER sourced into the shell. Scripts that need secrets use run-with-secrets.sh.
#
# Add this to your ~/.bashrc or ~/.zshrc:
#   [ -f ~/dotfiles/bin/load-secrets.sh ] && source ~/dotfiles/bin/load-secrets.sh
#
# Works on: Windows (Git Bash/MSYS2), Linux (VPS), macOS

_DOTFILES_ENV_AGENT="$HOME/dotfiles/secrets/.env.agent"

_source_env() {
    local _tmp _prev_allexport _prev_int_trap _prev_hup_trap _prev_term_trap
    _prev_allexport=$(set +o | grep allexport)
    _prev_int_trap=$(trap -p INT || true)
    _prev_hup_trap=$(trap -p HUP || true)
    _prev_term_trap=$(trap -p TERM || true)
    _tmp=$(mktemp) || { printf '\033[31m[dotfiles] mktemp failed — cannot load %s\033[0m\n' "$1" >&2; return 1; }
    _restore_source_env_traps() {
        if [[ -n "$_prev_int_trap" ]]; then eval "$_prev_int_trap"; else trap - INT; fi
        if [[ -n "$_prev_hup_trap" ]]; then eval "$_prev_hup_trap"; else trap - HUP; fi
        if [[ -n "$_prev_term_trap" ]]; then eval "$_prev_term_trap"; else trap - TERM; fi
    }
    _cleanup_source_env_tmp() {
        rm -f "$_tmp" 2>/dev/null || true
        _restore_source_env_traps
        unset -f _cleanup_source_env_tmp _restore_source_env_traps
    }
    trap '_cleanup_source_env_tmp; return 130' INT HUP TERM
    tr -d '\r' < "$1" > "$_tmp"
    set -a
    if ! source "$_tmp"; then
        printf '\033[31m[dotfiles] Syntax error in %s — fix the file and re-source\033[0m\n' "$1" >&2
        eval "$_prev_allexport"
        _cleanup_source_env_tmp
        return 1
    fi
    eval "$_prev_allexport"
    _cleanup_source_env_tmp
}

if [ -f "$_DOTFILES_ENV_AGENT" ]; then
    _source_env "$_DOTFILES_ENV_AGENT"
else
    printf '\033[33m[dotfiles] secrets/.env.agent not found — run: cp ~/dotfiles/.env.agent.example ~/dotfiles/secrets/.env.agent\033[0m\n' >&2
fi

unset -f _source_env

# Ensure GitHub CLI is available in Git Bash sessions on Windows.
# Some shells miss this path even when gh is installed via WinGet.
if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* || "$OSTYPE" == win32* ]]; then
    _gh_dir="/c/Program Files/GitHub CLI"
    if [[ -x "$_gh_dir/gh.exe" ]] && ! command -v gh >/dev/null 2>&1; then
        export PATH="$_gh_dir:$PATH"
    fi
    unset _gh_dir
fi

# Ensure jq is available in Git Bash sessions on Windows (used by git hooks
# and the ctrl/shft CLIs for JSON inspection). Installed locally to C:\Tools\jq
# on this machine (winget wasn't available); add it if present.
if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* || "$OSTYPE" == win32* ]]; then
    _jq_dir="/c/Tools/jq"
    if [[ -x "$_jq_dir/jq.exe" ]] && ! command -v jq >/dev/null 2>&1; then
        export PATH="$_jq_dir:$PATH"
    fi
    unset _jq_dir
fi

unset _DOTFILES_ENV_AGENT
