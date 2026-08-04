#!/usr/bin/env bash
# verify-pr-base.sh — Resolve the authoritative base branch for the current
# branch, and optionally verify the branch contains no commits from a sibling
# base that aren't in the PR's actual base.
#
# WHY THIS EXISTS
#   The eval that motivated this: an agent merged origin/dev into a PR whose
#   base was main, dragging ~125 unrelated files into a 4-file PR, and pushed
#   it to the remote before checking. Root cause: the atomic-commits skill
#   GUESSED the base branch (picked whichever of dev/main/master exists on the
#   remote) instead of resolving the PR's actual base. This script is the
#   single source of truth for base resolution so skills and hooks never guess.
#
# RESOLUTION ORDER (authoritative, never guessed):
#   1. --pr <N>  → gh pr view <N> --json baseRefName --jq .baseRefName
#   2. --branch <ref> with an open PR → gh pr view --json baseRefName
#   3. sandcastle.config.json "baseBranch" (repo convention; ctrlshft = dev)
#   4. gh repo view --json defaultBranchRef (GitHub default; ctrlshft = main)
#
#   Order matters: sandcastle.config.json baseBranch must come BEFORE the
#   GitHub default branch, because ctrlshft's GitHub default is main but new
#   PRs target dev.
#
# USAGE
#   bin/verify-pr-base.sh [--pr <N>] [--branch <ref>] [--check-ancestry]
#     --pr <N>          Resolve base for PR <N> (authoritative).
#     --branch <ref>    Resolve base for branch <ref> (default: current branch).
#     --check-ancestry  Also verify the branch contains no commits from a
#                       sibling base that aren't in the resolved base. Exits 1
#                       if it does (wrong base was merged in).
#     --quiet           Suppress the resolved-base line on stdout.
#
#   Prints the resolved base branch name to stdout (unless --quiet).
#   Exit 0 = resolved (and, with --check-ancestry, ancestry is clean).
#   Exit 1 = could not resolve, or ancestry check failed.
#   Exit 2 = usage error.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

PR=""
BRANCH=""
CHECK_ANCESTRY=0
QUIET=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pr) PR="${2:-}"; shift 2 ;;
        --branch) BRANCH="${2:-}"; shift 2 ;;
        --check-ancestry) CHECK_ANCESTRY=1; shift ;;
        --quiet) QUIET=1; shift ;;
        *) echo "verify-pr-base: unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$PR" && -z "$BRANCH" ]]; then
    BRANCH="$(git branch --show-current 2>/dev/null || true)"
fi

if [[ -z "$PR" && -z "$BRANCH" ]]; then
    echo "verify-pr-base: could not determine current branch (detached HEAD?)" >&2
    exit 1
fi

# ── Resolve the base ─────────────────────────────────────────────────────────
BASE=""

# 1. Explicit PR number — authoritative.
if [[ -n "$PR" ]]; then
    if ! command -v gh >/dev/null 2>&1; then
        echo "verify-pr-base: --pr requires the gh CLI (not found)" >&2
        exit 1
    fi
    BASE="$(gh pr view "$PR" --json baseRefName --jq .baseRefName 2>/dev/null || true)"
    if [[ -z "$BASE" ]]; then
        echo "verify-pr-base: could not resolve base for PR #$PR (gh pr view failed)" >&2
        exit 1
    fi
fi

# 2. Branch with an open PR — authoritative.
if [[ -z "$BASE" && -n "$BRANCH" ]] && command -v gh >/dev/null 2>&1; then
    BASE="$(gh pr view "$BRANCH" --json baseRefName --jq .baseRefName 2>/dev/null || true)"
fi

# 3. sandcastle.config.json baseBranch — repo convention.
if [[ -z "$BASE" && -f "$ROOT/sandcastle.config.json" ]] && command -v jq >/dev/null 2>&1; then
    BASE="$(jq -r '.baseBranch // empty' "$ROOT/sandcastle.config.json" 2>/dev/null || true)"
fi

# 4. GitHub default branch — last resort.
if [[ -z "$BASE" ]] && command -v gh >/dev/null 2>&1; then
    BASE="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || true)"
fi

if [[ -z "$BASE" ]]; then
    echo "verify-pr-base: could not resolve base branch (no PR, no sandcastle.config.json, no gh)" >&2
    echo "verify-pr-base: refusing to guess — resolve the base explicitly and retry." >&2
    exit 1
fi

# ── Ancestry check (optional) ────────────────────────────────────────────────
# Verify the branch does not contain commits from a sibling base that aren't
# in the resolved base. This catches the eval's exact failure: a main-based PR
# that had origin/dev merged in. Sibling-only commits (base..sibling) that
# appear in HEAD mean a wrong base was merged.
if [[ "$CHECK_ANCESTRY" -eq 1 ]]; then
    if [[ -z "$BRANCH" ]]; then
        echo "verify-pr-base: --check-ancestry requires a branch (use --branch or be on one)" >&2
        exit 2
    fi
    if ! git rev-parse --verify "origin/$BASE" >/dev/null 2>&1; then
        echo "verify-pr-base: origin/$BASE not found — cannot verify ancestry" >&2
        exit 1
    fi
    for candidate in dev main master; do
        [[ "$candidate" == "$BASE" ]] && continue
        git rev-parse --verify "origin/$candidate" >/dev/null 2>&1 || continue
        # Commits reachable from the sibling but not from the resolved base.
        foreign="$(git rev-list "origin/$BASE..origin/$candidate" 2>/dev/null || true)"
        [[ -z "$foreign" ]] && continue
        # Any of those foreign commits present in HEAD?
        if git rev-list "origin/$BASE..HEAD" 2>/dev/null | grep -qxF -f <(printf '%s\n' "$foreign"); then
            echo "verify-pr-base: branch '$BRANCH' contains commits from '$candidate' that are not in its base '$BASE'." >&2
            echo "verify-pr-base: a wrong base was merged in. Rebase onto origin/$BASE and drop the '$candidate' merge." >&2
            exit 1
        fi
    done
fi

if [[ "$QUIET" -eq 0 ]]; then
    printf '%s\n' "$BASE"
fi
exit 0
