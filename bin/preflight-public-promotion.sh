#!/usr/bin/env bash
# preflight-public-promotion.sh — Validate candidate commits before public ctrlshft promotion.
#
# This is the range-based promotion workflow. It checks only the candidate
# commit range so safe public history can be promoted without carrying private
# containment/runtime state along for the ride.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES="${DOTFILES:-$(cd "$SCRIPT_DIR/.." && pwd)}"
source "$DOTFILES/bin/_lib.sh"

RANGE=""
REMOTE="public"
BRANCH="main"
PUSH=false
CONFIRM_PUBLIC_PUSH=false
CANDIDATE_PATHS_LOADED=false
CANDIDATE_PATHS=()
_fail=0

usage() {
    cat <<'USAGE'
Usage: bash bin/preflight-public-promotion.sh --range <rev-range> [options]

Validates candidate commits before promoting them to public ctrlshft.

Options:
  --range <rev-range>        Candidate commit range, e.g. public/main..HEAD
  --remote <name>            Public remote to push to (default: public)
  --branch <name>            Public branch target (default: main)
  --push                     Push HEAD to the public remote after preflight
  --confirm-public-push      Required with --push
  --help, -h                 Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --range)
            RANGE="${2:-}"
            if [[ -z "$RANGE" ]]; then
                red "Missing value for --range"
                exit 1
            fi
            shift 2
            ;;
        --remote)
            REMOTE="${2:-}"
            if [[ -z "$REMOTE" ]]; then
                red "Missing value for --remote"
                exit 1
            fi
            shift 2
            ;;
        --branch)
            BRANCH="${2:-}"
            if [[ -z "$BRANCH" ]]; then
                red "Missing value for --branch"
                exit 1
            fi
            shift 2
            ;;
        --push)
            PUSH=true
            shift
            ;;
        --confirm-public-push)
            CONFIRM_PUBLIC_PUSH=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            red "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    red "  ✗ Not inside a Git worktree"
    exit 1
fi

if [[ -z "$RANGE" ]]; then
    if git rev-parse --verify "refs/remotes/$REMOTE/$BRANCH" >/dev/null 2>&1; then
        RANGE="$REMOTE/$BRANCH..HEAD"
    else
        red "  ✗ Missing --range and cannot resolve $REMOTE/$BRANCH"
        red "    Example: bash bin/preflight-public-promotion.sh --range public/main..HEAD"
        exit 1
    fi
fi

if ! git rev-list --count "$RANGE" >/dev/null 2>&1; then
    red "  ✗ Invalid candidate range: $RANGE"
    exit 1
fi

private_reason() {
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

load_candidate_paths() {
    local path existing
    local seen

    if [[ "$CANDIDATE_PATHS_LOADED" == true ]]; then
        return
    fi

    while IFS= read -r -d '' path; do
        [[ -z "$path" ]] && continue

        seen=false
        for existing in "${CANDIDATE_PATHS[@]}"; do
            if [[ "$existing" == "$path" ]]; then
                seen=true
                break
            fi
        done

        if [[ "$seen" == false ]]; then
            CANDIDATE_PATHS+=("$path")
        fi
    done < <(git log --format='' --name-only -z --diff-filter=ACDMR "$RANGE")

    CANDIDATE_PATHS_LOADED=true
}

check_emergency_containment_commits() {
    local matches

    matches="$(git log --format='%h %s' "$RANGE" | grep -Ei 'emergency containment|local git topology|#86|personal access token|(^|[^A-Z])PAT([^A-Z]|$)' || true)"
    if [[ -z "$matches" ]]; then
        return 0
    fi

    red "  ✗ emergency containment commit(s) must be excluded from public promotion"
    while IFS= read -r line; do
        [[ -n "$line" ]] && red "    $line"
    done <<< "$matches"
    _fail=1
}

check_candidate_paths() {
    local path reason

    load_candidate_paths

    if [[ ${#CANDIDATE_PATHS[@]} -eq 0 ]]; then
        yellow "  ~ Candidate range has no changed paths"
        return 0
    fi

    green "  ✓ Candidate range has ${#CANDIDATE_PATHS[@]} changed path(s)"

    for path in "${CANDIDATE_PATHS[@]}"; do
        if reason="$(private_reason "$path")"; then
            red "  ✗ unsafe path in candidate range: $path"
            red "    $reason"
            _fail=1
        fi
    done
}

check_sandcastle_private_refs() {
    local files=()
    local commit path matches

    load_candidate_paths

    for path in "${CANDIDATE_PATHS[@]}"; do
        [[ "$path" == .sandcastle/* ]] || continue
        files+=("$path")
    done

    if [[ ${#files[@]} -eq 0 ]]; then
        return 0
    fi

    for commit in $(git rev-list --reverse "$RANGE"); do
        matches="$(git grep -nIE 'dotfiles-private|~/dotfiles|arndvs/dotfiles-private|C:\\Users\\aaron|/Users/aaron' "$commit" -- "${files[@]}" 2>/dev/null || true)"
        if [[ -z "$matches" ]]; then
            continue
        fi

        red "  ✗ .sandcastle contains private repo or local-machine references"
        while IFS= read -r line; do
            red "    $line"
        done <<< "$matches"
        _fail=1
    done

    if [[ $_fail -eq 0 ]]; then
        green "  ✓ .sandcastle candidate history has no private repo/local-machine references"
    fi
}

check_secret_like_values() {
    local files=()
    local commit path file bad_files

    load_candidate_paths

    for path in "${CANDIDATE_PATHS[@]}"; do
        files+=("$path")
    done

    if [[ ${#files[@]} -eq 0 ]]; then
        return 0
    fi

    for commit in $(git rev-list --reverse "$RANGE"); do
        bad_files="$(git grep -lIE 'ghp_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----' "$commit" -- "${files[@]}" 2>/dev/null || true)"
        if [[ -z "$bad_files" ]]; then
            continue
        fi

        red "  ✗ high-confidence secret-like values found in candidate history"
        while IFS= read -r file; do
            [[ -n "$file" ]] && red "    $file"
        done <<< "$bad_files"
        _fail=1
    done

    if [[ $_fail -eq 0 ]]; then
        green "  ✓ Candidate history has no high-confidence secret-like values"
    fi
}

echo "Public Promotion Preflight:"
echo "  Range:  $RANGE"
echo "  Target: $REMOTE/$BRANCH"

check_emergency_containment_commits
check_candidate_paths
check_sandcastle_private_refs
check_secret_like_values

if [[ $_fail -ne 0 ]]; then
    red ""
    red "Public promotion preflight failed."
    exit 1
fi

green "  ✓ Public promotion preflight passed"

if [[ "$PUSH" == true ]]; then
    if [[ "$CONFIRM_PUBLIC_PUSH" != true ]]; then
        red "  ✗ --push requires --confirm-public-push"
        exit 1
    fi
    green "  ✓ Explicit public push confirmation received"
    CTRL_ALLOW_PUBLIC_PUSH=1 git push "$REMOTE" "HEAD:$BRANCH"
fi
