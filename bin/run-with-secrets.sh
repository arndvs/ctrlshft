#!/usr/bin/env bash
# run-with-secrets.sh — Execute a command with secrets injected into its process only.
#
# Secrets from secrets/.env.secrets are available ONLY to the child process.
# They never enter the parent shell or agent environment.
#
# Usage:
#   ~/dotfiles/bin/run-with-secrets.sh python scripts/sheets_client.py
#   ~/dotfiles/bin/run-with-secrets.sh node scripts/deploy.js
#
# The child process inherits the current shell environment (which already has
# .env.agent vars from load-secrets.sh) PLUS the secrets. When the process
# exits, the secrets are gone.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

_SECRETS_FILE="$HOME/dotfiles/secrets/.env.secrets"



if [[ $# -eq 0 ]]; then
    echo "Usage: run-with-secrets.sh <command> [args...]" >&2
    echo "Runs <command> with secrets/.env.secrets injected into the process environment." >&2
    exit 1
fi

if [[ -f "$_SECRETS_FILE" ]]; then
    _tmp=$(mktemp) || { red "[run-with-secrets] mktemp failed" >&2; exit 1; }
    trap 'rm -f "$_tmp" 2>/dev/null' EXIT
    tr -d '\r' < "$_SECRETS_FILE" | grep -v '^\s*#' | grep -v '^\s*$' > "$_tmp"
    if [[ ! -s "$_tmp" ]]; then
        red "[run-with-secrets] .env.secrets is empty or could not be parsed" >&2
        exit 1
    fi
    set -a
    if ! source "$_tmp"; then
        red "[run-with-secrets] Syntax error in .env.secrets — fix the file" >&2
        exit 1
    fi
    set +a
    rm -f "$_tmp"
    trap - EXIT
else
    red "[run-with-secrets] secrets/.env.secrets not found" >&2
    red "[run-with-secrets] Create from template: cp ~/dotfiles/.env.secrets.example ~/dotfiles/secrets/.env.secrets" >&2
    exit 1
fi

exec "$@"
