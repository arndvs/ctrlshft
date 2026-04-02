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

if [ -f "$_DOTFILES_ENV" ]; then
    set -a
    source "$_DOTFILES_ENV"
    set +a
fi

if [ -f "$_DOTFILES_ENV_CITATION" ]; then
    set -a
    source "$_DOTFILES_ENV_CITATION"
    set +a
fi

unset _DOTFILES_ENV _DOTFILES_ENV_CITATION
