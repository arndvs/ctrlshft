#!/usr/bin/env bash
# validate-public-promotion.sh — Block unsafe paths/content from public ctrlshft promotion.
#
# This guard is intentionally stricter than normal private checkout validation:
# private dotfiles may track runtime files, but those paths must not be pushed
# to the public ctrlshft tree by accident. The Sandcastle tree is promotable
# once content-level private references are sanitized.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES="${DOTFILES:-$(cd "$SCRIPT_DIR/.." && pwd)}"
source "$DOTFILES/bin/_lib.sh"

_fail=0

case "${1:-}" in
    --help|-h)
        echo "Usage: bash bin/validate-public-promotion.sh"
        echo ""
        echo "Fails if the current Git index contains private-only paths or"
        echo "unsafe .sandcastle content that must not be promoted to public ctrlshft."
        exit 0
        ;;
    "")
        ;;
    *)
        red "Unknown option: $1"
        red "Usage: bash bin/validate-public-promotion.sh"
        exit 1
        ;;
esac

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    red "  ✗ Not inside a Git worktree"
    exit 1
fi

_private_reason() {
    local path="$1"

    case "$path" in
        working/active/*|working/runtime/*|working/tmp/*|working/logs/*|working/refs/*|working/research/*)
            printf '%s\n' "working-state artifact; promote durable material under docs/ instead"
            return 0
            ;;
        working/*.log|working/*.json|working/*.jsonl)
            printf '%s\n' "runtime state file"
            return 0
            ;;
        secrets/README.md|secrets/.env.agent.example|secrets/.env.bridge.example)
            return 1
            ;;
        secrets/*)
            printf '%s\n' "private secrets path"
            return 0
            ;;
        .env|.env.*)
            case "$path" in
                .env.agent.example|.env.secrets.example|.env.citation.example)
                    return 1
                    ;;
            esac
            printf '%s\n' "local environment file"
            return 0
            ;;
    esac

    return 1
}

_scan_sandcastle_private_refs() {
    local matches

    matches="$(git grep -nIE 'dotfiles-private|~/dotfiles|arndvs/dotfiles-private|C:\\Users\\aaron|/Users/aaron' -- .sandcastle 2>/dev/null || true)"
    if [[ -z "$matches" ]]; then
        return 0
    fi

    red "  ✗ .sandcastle contains private repo or local-machine references"
    while IFS= read -r line; do
        red "    $line"
    done <<< "$matches"
    _fail=1
}

_scan_secret_values() {
    local files

    files="$(git grep -lIE 'ghp_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----' -- 2>/dev/null || true)"
    if [[ -z "$files" ]]; then
        return 0
    fi

    red "  ✗ high-confidence secret-like values found in tracked files"
    while IFS= read -r file; do
        red "    $file"
    done <<< "$files"
    _fail=1
}

echo "Public Promotion Guard:"

while IFS= read -r -d '' path; do
    if reason="$(_private_reason "$path")"; then
        red "  ✗ private-only path tracked for public promotion: $path"
        red "    $reason"
        _fail=1
    fi
done < <(git ls-files -z)

_scan_sandcastle_private_refs
_scan_secret_values

if [[ $_fail -eq 0 ]]; then
    green "  ✓ Public promotion guard passed"
    green "  ✓ Sanitized .sandcastle content is allowed for public promotion"
else
    red ""
    red "Public promotion blocked."
    red "Allowed Sandcastle promotion includes sanitized .sandcastle/** plus source paths under shft/."
    red "Do not promote private runtime state, local env files, or secret values."
fi

exit $_fail
