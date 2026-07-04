#!/usr/bin/env bash
# apply-branch-ruleset.sh — Apply the committed branch ruleset to GitHub.
#
# The ruleset in .github/rulesets/main.json is the SERVER-SIDE, identity-
# independent backstop that makes direct pushes and force-pushes to main
# impossible for ANY tool or agent. The local pre-push hook is the fast local
# layer; this is the one that cannot be bypassed by editing a local file.
#
# Phase 1 (this spec): require a PR to change main (blocks direct pushes),
# block force-pushes (non_fast_forward) and deletions. required_approving_
# review_count is 0 so a solo maintainer can still merge their own promotion PRs.
#
# Phase 2 (after the agent runs under a separate, NON-privileged identity):
# raise required_approving_review_count to 1 and require_code_owner_review to
# true, so an AI acting as the PR author can never approve→merge to main — a
# human must. With a shared identity that would also block the human, hence the
# Phase-1 default here.
#
# Idempotent: updates an existing ruleset of the same name, else creates it.
# Requires an admin-scoped `gh auth`.
#
# Usage: bash bin/apply-branch-ruleset.sh [--dry-run]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
REPO="${CTRLSHFT_RULESET_REPO:-arndvs/ctrlshft}"
SPEC="$ROOT/.github/rulesets/main.json"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

command -v gh >/dev/null 2>&1 || { echo "apply-branch-ruleset: gh CLI required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "apply-branch-ruleset: jq required" >&2; exit 1; }
[[ -f "$SPEC" ]] || { echo "apply-branch-ruleset: missing $SPEC" >&2; exit 1; }

NAME="$(jq -r '.name' "$SPEC")"

# Query existing rulesets. On PRIVATE repos without GitHub Pro/Team/Enterprise the
# rulesets API returns 403 ("Upgrade to GitHub Pro …") — detect that and fail loud
# with the real reason instead of emitting garbled output.
RULESETS_JSON="$(gh api "repos/$REPO/rulesets" 2>/dev/null || true)"
if printf '%s' "$RULESETS_JSON" | grep -q 'Upgrade to GitHub Pro\|"status": *"403"'; then
    echo "apply-branch-ruleset: rulesets are unavailable on '$REPO'." >&2
    echo "  GitHub requires Pro/Team/Enterprise for rulesets on a PRIVATE repo." >&2
    echo "  Options: upgrade the plan, make the repo public, or apply this ruleset to" >&2
    echo "  the public mirror. The local pre-push hook still guards main meanwhile." >&2
    exit 2
fi
EXISTING_ID="$(printf '%s' "$RULESETS_JSON" | jq -r ".[]? | select(.name==\"$NAME\") | .id" 2>/dev/null | head -1 || true)"

if $DRY_RUN; then
    echo "apply-branch-ruleset: DRY-RUN"
    echo "  repo:    $REPO"
    echo "  ruleset: $NAME"
    echo "  action:  $([[ -n "$EXISTING_ID" ]] && echo "update (id=$EXISTING_ID)" || echo "create")"
    echo "  spec:    $SPEC"
    exit 0
fi

if [[ -n "$EXISTING_ID" ]]; then
    gh api --method PUT "repos/$REPO/rulesets/$EXISTING_ID" --input "$SPEC" >/dev/null
    echo "apply-branch-ruleset: updated ruleset '$NAME' (id=$EXISTING_ID) on $REPO"
else
    gh api --method POST "repos/$REPO/rulesets" --input "$SPEC" >/dev/null
    echo "apply-branch-ruleset: created ruleset '$NAME' on $REPO"
fi
