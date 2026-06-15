#!/usr/bin/env bash
# validate-remotes.sh — Verify private/public Git remote topology.
#
# Expected topology for Aaron's private ~/dotfiles checkout:
#   origin -> arndvs/dotfiles-private (private canonical)
#   public -> arndvs/ctrlshft         (public/sanitized, push disabled)

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

EXPECTED_ORIGIN="$CTRLSHFT_PRIVATE_REMOTE_URL"
EXPECTED_PUBLIC="$CTRLSHFT_PUBLIC_REMOTE_URL"
DISABLED_PUSHURL="DISABLED"

_fail=0
_warn=0

normalize_url() {
    normalize_ctrlshft_remote_url "$1"
}

remote_url() {
    git config --get "remote.$1.url" 2>/dev/null || true
}

check_remote_url() {
    local remote="$1"
    local expected="$2"
    local label="$3"
    local actual
    actual="$(remote_url "$remote")"

    if [[ -z "$actual" ]]; then
        red "  ✗ Missing $remote remote ($label)"
        _fail=1
        return
    fi

    if [[ "$(normalize_url "$actual")" == "$expected" ]]; then
        green "  ✓ $remote -> $expected ($label)"
    else
        red "  ✗ $remote points to $actual (expected $expected — $label)"
        _fail=1
    fi
}

check_no_ctrlshft_upstream() {
    local upstream_url
    upstream_url="$(remote_url upstream)"
    if [[ -z "$upstream_url" ]]; then
        green "  ✓ No upstream remote configured"
        return
    fi

    if [[ "$(normalize_url "$upstream_url")" == "$EXPECTED_PUBLIC" ]]; then
        red "  ✗ upstream points to public ctrlshft; rename it to 'public' to avoid source-of-truth confusion"
        _fail=1
    else
        yellow "  ~ upstream exists but does not point to ctrlshft: $upstream_url"
        _warn=1
    fi
}

check_push_default() {
    local push_default
    push_default="$(git config --get remote.pushDefault 2>/dev/null || true)"

    case "$push_default" in
        ""|origin)
            green "  ✓ remote.pushDefault is safe (${push_default:-unset})"
            ;;
        public|upstream)
            red "  ✗ remote.pushDefault is $push_default (must be unset or origin)"
            _fail=1
            ;;
        *)
            yellow "  ~ remote.pushDefault is $push_default (review whether this is intentional)"
            _warn=1
            ;;
    esac
}

check_protected_branch_upstreams() {
    local branch branch_remote branch_merge remote_target
    local protected_branches=(main master dev develop)
    local bad=0

    for branch in "${protected_branches[@]}"; do
        if ! git show-ref --verify --quiet "refs/heads/$branch"; then
            continue
        fi

        branch_remote="$(git config --get "branch.$branch.remote" 2>/dev/null || true)"
        branch_merge="$(git config --get "branch.$branch.merge" 2>/dev/null || true)"

        [[ -z "$branch_remote" ]] && continue

        remote_target="$(remote_url "$branch_remote")"
        if [[ "$branch_remote" == "public" ]] || [[ "$branch_remote" == "upstream" ]] || [[ "$(normalize_url "$remote_target")" == "$EXPECTED_PUBLIC" ]]; then
            red "  ✗ protected branch '$branch' tracks public remote '$branch_remote' (${branch_merge:-no merge ref})"
            red "    Fix: git branch --set-upstream-to origin/$branch $branch"
            bad=1
        fi
    done

    if [[ $bad -eq 0 ]]; then
        green "  ✓ Protected branches do not track public remotes"
    else
        _fail=1
    fi
}

check_public_push_disabled() {
    local push_urls
    push_urls="$(git config --get-all remote.public.pushurl 2>/dev/null || true)"

    if [[ -z "$push_urls" ]]; then
        red "  ✗ public has no pushurl override; Git will push to the public fetch URL by default"
        red "    Fix: git remote set-url --push public $DISABLED_PUSHURL"
        _fail=1
        return
    fi

    local bad=0
    while IFS= read -r push_url; do
        [[ -z "$push_url" ]] && continue
        if [[ "$push_url" != "$DISABLED_PUSHURL" ]]; then
            bad=1
            red "  ✗ public pushurl is enabled: $push_url"
        fi
    done <<< "$push_urls"

    if [[ $bad -eq 0 ]]; then
        green "  ✓ public push URL is disabled"
    else
        red "    Fix: git remote set-url --push public $DISABLED_PUSHURL"
        _fail=1
    fi
}

is_private_checkout() {
    local remote actual
    while IFS= read -r remote; do
        actual="$(remote_url "$remote")"
        if [[ "$(normalize_url "$actual")" == "$EXPECTED_ORIGIN" ]]; then
            return 0
        fi
    done < <(git remote)

    return 1
}

check_public_content_sanitization() {
    local matches
    echo
    echo "Content Sanitization:"

    matches="$(git grep -nIE '(git@github\.com:|https://github\.com/)arndvs/dotfiles-private(\.git)?' -- ':!bin/validate-remotes.sh' 2>/dev/null || true)"
    if [[ -n "$matches" ]]; then
        red "  ✗ dotfiles-private URL references found in tracked files"
        while IFS= read -r line; do
            red "    $line"
        done <<< "$matches"
        _fail=1
    else
        green "  ✓ No dotfiles-private URLs in tracked files"
    fi
}

echo "Repository Remote Topology:"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    red "  ✗ Not inside a Git worktree"
    exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
if [[ "$(cd "$repo_root" && pwd -P)" != "$(cd "$HOME/dotfiles" && pwd -P)" ]]; then
    yellow "  ~ Running outside ~/dotfiles: $repo_root"
    _warn=1
fi

if ! is_private_checkout; then
    green "  ✓ Public/fork checkout detected; private dotfiles remote topology check skipped"
    check_public_content_sanitization
    exit $_fail
fi

check_remote_url origin "$EXPECTED_ORIGIN" "private canonical"
check_remote_url public "$EXPECTED_PUBLIC" "public sanitized"
check_no_ctrlshft_upstream
check_push_default
check_protected_branch_upstreams
check_public_push_disabled

if [[ $_fail -eq 0 ]] && [[ $_warn -eq 0 ]]; then
    green "  ✓ Repo topology is healthy"
elif [[ $_fail -eq 0 ]]; then
    yellow "  ~ Repo topology passed with warnings"
fi

exit $_fail