#!/usr/bin/env bash
# gh-assignee-preflight.sh — verify current gh auth context can assign issues.
#
# Usage:
#   bash ~/dotfiles/bin/gh-assignee-preflight.sh --repo owner/name [--assignee @me|username]
#
# Exit code:
#   0 = ready to assign
#   1 = not ready (prints concrete fix guidance)

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

repo=""
assignee="@me"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)
            repo="${2:-}"
            shift 2
            ;;
        --assignee)
            assignee="${2:-}"
            shift 2
            ;;
        -h|--help)
            cat <<'EOF'
Usage:
  bash ~/dotfiles/bin/gh-assignee-preflight.sh --repo owner/name [--assignee @me|username]

Examples:
  bash ~/dotfiles/bin/gh-assignee-preflight.sh --repo arndvs/launch
  bash ~/dotfiles/bin/gh-assignee-preflight.sh --repo arndvs/launch --assignee arndvs
EOF
            exit 0
            ;;
        *)
            red "Unknown argument: $1"
            exit 1
            ;;
    esac
done

if [[ -z "$repo" ]]; then
    red "Missing required --repo owner/name"
    exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
    red "GitHub CLI (gh) is not installed or not on PATH."
    exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
    red "gh is not authenticated. Run: gh auth login"
    exit 1
fi

has_env_override=0
if [[ -n "${GH_TOKEN:-}" ]] || [[ -n "${GITHUB_TOKEN:-}" ]]; then
    has_env_override=1
fi

resolved_assignee="$assignee"
if [[ "$assignee" == "@me" ]]; then
    if ! resolved_assignee=$(gh api user --jq '.login' 2>/dev/null); then
        red "Cannot resolve @me to a user login with current token context."
        red "Likely cause: gh is using a non-user token type (for example an app/integration token)."
        red "Fix: unset GH_TOKEN/GITHUB_TOKEN for this shell, then run 'gh auth login' and retry."
        exit 1
    fi
fi

if [[ $has_env_override -eq 1 ]] && [[ "$assignee" == "@me" ]]; then
    yellow "Environment token override detected (GH_TOKEN or GITHUB_TOKEN is set)."
    yellow "This can force a token type that cannot use @me assignment in some contexts."
fi

if ! gh api "repos/$repo" --jq '.nameWithOwner' >/dev/null 2>&1; then
    red "Current token cannot access repository '$repo'."
    red "Fix: authenticate with a token that has issue write access to this repo."
    exit 1
fi

if ! gh api "repos/$repo/assignees/$resolved_assignee" >/dev/null 2>&1; then
    red "User '$resolved_assignee' is not assignable in '$repo' with current auth context."
    red "Fix options:"
    red "  1) Ensure '$resolved_assignee' has repository access"
    red "  2) Use a user token with issue assignment permissions"
    red "  3) If using automation/app tokens, avoid @me and pass an explicit username"
    exit 1
fi

green "Preflight passed: assignment should work for '$resolved_assignee' in '$repo'."
green "Safe command: gh issue edit <number> --add-assignee $resolved_assignee --repo $repo"
