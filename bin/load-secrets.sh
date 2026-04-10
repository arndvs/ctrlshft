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
    local _tmp _prev_allexport
    _prev_allexport=$(set +o | grep allexport)
    _tmp=$(mktemp) || { printf '\033[31m[dotfiles] mktemp failed — cannot load %s\033[0m\n' "$1" >&2; return 1; }
    tr -d '\r' < "$1" > "$_tmp"
    set -a
    source "$_tmp" 2>/dev/null
    eval "$_prev_allexport"
    rm -f "$_tmp"
}

if [ -f "$_DOTFILES_ENV_AGENT" ]; then
    _source_env "$_DOTFILES_ENV_AGENT"
else
    printf '\033[33m[dotfiles] secrets/.env.agent not found — run: cp ~/dotfiles/.env.agent.example ~/dotfiles/secrets/.env.agent\033[0m\n' >&2
fi

unset -f _source_env

unset _DOTFILES_ENV_AGENT
