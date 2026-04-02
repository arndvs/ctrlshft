#!/usr/bin/env bash
# load-secrets.sh — Source centralized secrets into the current shell.
#
# Add this to your ~/.bashrc or ~/.zshrc:
#   [ -f ~/dotfiles/bin/load-secrets.sh ] && source ~/dotfiles/bin/load-secrets.sh
#
# Works on: Windows (Git Bash/MSYS2), Linux (VPS), macOS
# For OpenClaw: set each var in their secrets UI instead — same names.

_DOTFILES_ENV="$HOME/dotfiles/secrets/.env"
_DOTFILES_ENV_CITATION="$HOME/dotfiles/secrets/.env.citation"

_source_env() {
    local _tmp
    _tmp=$(mktemp)
    tr -d '\r' < "$1" > "$_tmp"
    set -a
    source "$_tmp"
    set +a
    rm -f "$_tmp"
}

if [ -f "$_DOTFILES_ENV" ]; then
    _source_env "$_DOTFILES_ENV"
fi

if [ -f "$_DOTFILES_ENV_CITATION" ]; then
    _source_env "$_DOTFILES_ENV_CITATION"
fi

unset -f _source_env

unset _DOTFILES_ENV _DOTFILES_ENV_CITATION
