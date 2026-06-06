#!/usr/bin/env bash
# validate-remotes.sh — Validate git remote topology for the private/public repo split.
#
# In a private repo checkout:
#   - origin should point to dotfiles-private
#   - public should point to ctrlshft
#   - pushDefault should be origin
#   - public push URL should be disabled
#
# In a public repo checkout (fork of ctrlshft):
#   - origin should point to the user's fork or ctrlshft
#   - No dotfiles-private push URLs anywhere
#
# Usage:
#   bash bin/validate-remotes.sh [--ci]
#
# Exit code: 0 if all checks pass, 1 if any fail.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

_fail=0
_warn=0
_ci_mode=0

for arg in "$@"; do
    case "$arg" in
        --ci) _ci_mode=1 ;;
        *)
            red "Unknown option: $arg"
            red "Usage: bash bin/validate-remotes.sh [--ci]"
            exit 1
            ;;
    esac
done

# Must be in a git repo
if ! git rev-parse --git-dir >/dev/null 2>&1; then
    red "  ✗ Not a git repository"
    exit 1
fi

echo "Remote Topology:"

# ── Detect mode: private vs public clone ─────────────────────────────────────
_origin_url=$(git remote get-url origin 2>/dev/null || echo "")
_is_private=0

if [[ "$_origin_url" == *"dotfiles-private"* ]]; then
    _is_private=1
    green "  ✓ Detected private repo (origin → dotfiles-private)"
elif [[ "$_origin_url" == *"ctrlshft"* ]]; then
    green "  ✓ Detected public repo (origin → ctrlshft)"
elif [[ -n "$_origin_url" ]]; then
    yellow "  ~ origin URL does not match known patterns: $_origin_url"
    _warn=1
else
    red "  ✗ No origin remote configured"
    _fail=1
fi

# ── Private repo checks ─────────────────────────────────────────────────────
if [[ $_is_private -eq 1 ]]; then
    # Check public remote exists
    _public_url=$(git remote get-url public 2>/dev/null || echo "")
    if [[ "$_public_url" == *"ctrlshft"* ]]; then
        green "  ✓ public remote points to ctrlshft"
    elif [[ -n "$_public_url" ]]; then
        red "  ✗ public remote URL unexpected: $_public_url"
        _fail=1
    else
        red "  ✗ public remote not configured"
        _fail=1
    fi

    # Check pushDefault
    _push_default=$(git config remote.pushDefault 2>/dev/null || echo "")
    if [[ "$_push_default" == "origin" ]]; then
        green "  ✓ pushDefault is origin"
    elif [[ -z "$_push_default" ]]; then
        yellow "  ~ pushDefault not set (recommended: git config remote.pushDefault origin)"
        _warn=1
    else
        yellow "  ~ pushDefault is '$_push_default' (expected: origin)"
        _warn=1
    fi

    # Check public push URL is disabled
    _public_push_url=$(git config "remote.public.pushurl" 2>/dev/null || echo "")
    if [[ "$_public_push_url" == "DISABLED"* ]] || [[ "$_public_push_url" == "no_push"* ]]; then
        green "  ✓ public push URL is disabled"
    elif [[ -z "$_public_push_url" ]]; then
        yellow "  ~ public push URL not explicitly disabled (recommend: git config remote.public.pushurl DISABLED)"
        _warn=1
    else
        red "  ✗ public push URL is active: $_public_push_url"
        _fail=1
    fi
fi

# ── Universal check: no dotfiles-private push URLs in tracked files ──────────
echo
echo "Content Sanitization:"

# Check tracked files for dotfiles-private push URLs (name references are OK)
_leaks=$(git grep -l "dotfiles-private" -- ':(exclude)REPO_TOPOLOGY.md' ':(exclude)CONTEXT.md' ':(exclude)*.md' 2>/dev/null || true)
if [[ -n "$_leaks" ]]; then
    # Filter to only actual push URL patterns, not documentation references
    _real_leaks=""
    while IFS= read -r file; do
        if grep -qE '(push|url|clone|fetch).*dotfiles-private' "$file" 2>/dev/null; then
            _real_leaks="$_real_leaks $file"
        fi
    done <<< "$_leaks"

    if [[ -n "${_real_leaks// /}" ]]; then
        red "  ✗ dotfiles-private push/url references found in:$_real_leaks"
        _fail=1
    else
        green "  ✓ No dotfiles-private push URLs in tracked files"
    fi
else
    green "  ✓ No dotfiles-private references in non-markdown tracked files"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo
if [[ $_fail -eq 0 ]] && [[ $_warn -eq 0 ]]; then
    green "Remote topology OK."
elif [[ $_fail -eq 0 ]]; then
    yellow "Remote topology OK with warnings."
else
    red "Remote topology has errors — review above."
fi

exit $_fail
