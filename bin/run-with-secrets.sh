#!/usr/bin/env bash
# run-with-secrets.sh — Execute a command with secrets injected into its process only.
#
# Secrets from secrets/.env.secrets are available ONLY to the child process.
# They never enter the parent shell or agent environment.
#
# Usage:
#   ~/dotfiles/bin/run-with-secrets.sh python scripts/sheets_client.py
#   ~/dotfiles/bin/run-with-secrets.sh node scripts/deploy.js
#   ~/dotfiles/bin/run-with-secrets.sh --only GITHUB_APP_ID,GITHUB_APP_INSTALLATION_ID -- command
#
# The child process inherits the current shell environment (which already has
# .env.agent vars from load-secrets.sh) PLUS the secrets. When the process
# exits, the secrets are gone.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

_SECRETS_FILE="$HOME/dotfiles/secrets/.env.secrets"
_ONLY_VARS=()

if [[ "${1:-}" == "--only" ]]; then
    shift
    if [[ $# -eq 0 ]] || [[ -z "${1:-}" ]]; then
        red "[run-with-secrets] --only requires a comma-separated variable list" >&2
        exit 1
    fi
    IFS=',' read -r -a _ONLY_VARS <<< "$1"
    shift
    if [[ "${1:-}" == "--" ]]; then
        shift
    fi
    for _var in "${_ONLY_VARS[@]}"; do
        if [[ ! "$_var" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            red "[run-with-secrets] Invalid --only variable name: $_var" >&2
            exit 1
        fi
    done
fi

if [[ $# -eq 0 ]]; then
    echo "Usage: run-with-secrets.sh <command> [args...]" >&2
    echo "       run-with-secrets.sh --only VAR1,VAR2 -- <command> [args...]" >&2
    echo "Runs <command> with secrets/.env.secrets injected into the process environment." >&2
    exit 1
fi

if [[ -f "$_SECRETS_FILE" ]]; then
    _tmp=$(mktemp) || { red "[run-with-secrets] mktemp failed" >&2; exit 1; }
    _source_tmp="$_tmp"
    trap 'rm -f "$_tmp" "${_filtered_tmp:-}" 2>/dev/null' EXIT
    tr -d '\r' < "$_SECRETS_FILE" | grep -v '^\s*#' | grep -v '^\s*$' > "$_tmp"
    if [[ ! -s "$_tmp" ]]; then
        red "[run-with-secrets] .env.secrets is empty or could not be parsed" >&2
        exit 1
    fi
    if ! awk '
        /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
        /^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=/ { next }
        { printf "line %d: expected KEY=value assignment\n", NR; bad=1 }
        END { exit bad }
    ' "$_tmp" >&2; then
        red "[run-with-secrets] Syntax error in .env.secrets — expected KEY=value assignments" >&2
        exit 1
    fi
    if [[ ${#_ONLY_VARS[@]} -gt 0 ]]; then
        _filtered_tmp=$(mktemp) || { red "[run-with-secrets] mktemp failed" >&2; exit 1; }
        : > "$_filtered_tmp"
        for _var in "${_ONLY_VARS[@]}"; do
            grep -E "^[[:space:]]*(export[[:space:]]+)?${_var}=" "$_tmp" >> "$_filtered_tmp" || true
        done
        if [[ ! -s "$_filtered_tmp" ]]; then
            red "[run-with-secrets] None of the requested --only variables are configured" >&2
            exit 1
        fi
        _source_tmp="$_filtered_tmp"
    fi
    set -a
    if ! source "$_source_tmp"; then
        red "[run-with-secrets] Syntax error in .env.secrets — fix the file" >&2
        exit 1
    fi
    set +a
    rm -f "$_tmp" "${_filtered_tmp:-}"
    trap - EXIT
else
    red "[run-with-secrets] secrets/.env.secrets not found" >&2
    red "[run-with-secrets] Create from template: cp ~/dotfiles/.env.secrets.example ~/dotfiles/secrets/.env.secrets" >&2
    exit 1
fi

exec "$@"
