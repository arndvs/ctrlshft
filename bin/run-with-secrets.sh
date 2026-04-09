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

_SECRETS_FILE="$HOME/dotfiles/secrets/.env.secrets"



if [[ $# -eq 0 ]]; then
    echo "Usage: run-with-secrets.sh <command> [args...]" >&2
    echo "Runs <command> with secrets/.env.secrets injected into the process environment." >&2
    exit 1
fi

if [[ -f "$_SECRETS_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source <(tr -d '\r' < "$_SECRETS_FILE" | grep -v '^\s*#' | grep -v '^\s*$')
    set +a
else
    printf '\033[31m[run-with-secrets] secrets/.env.secrets not found\033[0m\n' >&2
    printf '\033[31m[run-with-secrets] Create from template: cp ~/dotfiles/.env.secrets.example ~/dotfiles/secrets/.env.secrets\033[0m\n' >&2
    exit 1
fi

exec "$@"
