#!/usr/bin/env bash
# agent-shell.sh — Launch a secrets-free shell for AI agent sessions.
#
# Starts a clean shell with ONLY non-sensitive .env.agent config.
# No secrets from .env.secrets are in scope — agents cannot inherit them.
#
# Usage:
#   source ~/dotfiles/bin/agent-shell.sh        # replace current shell
#   bash ~/dotfiles/bin/agent-shell.sh           # launch subshell
#
# Launch VS Code from this shell for maximum isolation:
#   bash ~/dotfiles/bin/agent-shell.sh
#   code-insiders .

set -euo pipefail

_AGENT_ENV="$HOME/dotfiles/secrets/.env.agent"

if [[ ! -f "$_AGENT_ENV" ]]; then
    printf '\033[31m[agent-shell] secrets/.env.agent not found\033[0m\n' >&2
    exit 1
fi

# Shared rcfile content — used by both Windows and Linux/macOS paths
_AGENT_RCFILE=$(cat << 'RCEOF'
# Minimal agent-safe rc
source <(tr -d '\r' < ~/dotfiles/secrets/.env.agent) 2>/dev/null
[[ -f ~/dotfiles/bin/detect-context.sh ]] && source ~/dotfiles/bin/detect-context.sh > /dev/null 2>&1
_load_context() { [[ -f ~/dotfiles/bin/detect-context.sh ]] && source ~/dotfiles/bin/detect-context.sh > /dev/null 2>&1; }
cd() { builtin cd "$@" && _load_context; }
PS1='\[\033[33m\][agent-shell]\[\033[0m\] \w\$ '
RCEOF
)

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        # env -i strips MSYS2 internals (MSYSTEM, TMP, path translation) — skip it on Windows
        printf '\033[33m[agent-shell] Git Bash detected — skipping env -i (not supported)\033[0m\n' >&2
        exec bash --rcfile <(printf '%s' "$_AGENT_RCFILE")
        ;;
    *)
        exec env -i \
            HOME="$HOME" \
            PATH="$PATH" \
            USER="${USER:-$(whoami)}" \
            TERM="${TERM:-xterm-256color}" \
            SHELL="${SHELL:-/bin/bash}" \
            LANG="${LANG:-en_US.UTF-8}" \
            bash --rcfile <(printf '%s' "$_AGENT_RCFILE")
        ;;
esac
