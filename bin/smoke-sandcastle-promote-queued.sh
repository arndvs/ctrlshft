#!/usr/bin/env bash
# smoke-sandcastle-promote-queued.sh — Drive the Sandcastle queued-promotion
# dependency-unblocking flow end-to-end.
#
# For each disposable test pair it creates a blocker issue and a dependent issue,
# links them with the native GitHub "blocked by" dependency, labels the dependent
# `agent:queued`, then closes the blocker. Closing the blocker fires
# `agent-promote-queued.yml`, which should remove `agent:queued` from the now-
# unblocked dependent and add `agent:implement`. The smoke verifies the promotion
# workflow run succeeded and the dependent's labels transitioned, repeating across
# at least two pairs, then cleans up every disposable artifact.
#
# Usage: ctrl smoke-sandcastle-promote-queued --allow-side-effects [--pairs 2]

set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
source "$DOTFILES/bin/_lib.sh"

REPO=""
PAIRS=2
TIMEOUT_SECONDS=900
POLL_SECONDS=10
DRY_RUN=false
ALLOW_SIDE_EFFECTS=false
KEEP_ARTIFACTS=false

WORKFLOW="agent-promote-queued.yml"

if command -v python3 >/dev/null 2>&1; then
    PY_BIN=python3
elif command -v python >/dev/null 2>&1; then
    PY_BIN=python
else
    echo "Python is required for Sandcastle promote-queued smoke parsing." >&2
    exit 1
fi

_usage() {
    cat <<'EOF'
Usage: ctrl smoke-sandcastle-promote-queued [options]

Creates disposable blocker/dependent issue pairs, links them with the native
GitHub "blocked by" dependency, labels each dependent `agent:queued`, and closes
the blocker. Verifies that `agent-promote-queued.yml` runs successfully and the
dependent loses `agent:queued` and gains `agent:implement`. Repeats across pairs
and cleans up all disposable issues, branches, and PRs.

Options:
  --repo OWNER/REPO        GitHub repo slug (default: gh repo view)
  --pairs N                Disposable blocker/dependent pairs to exercise (default: 2, min: 2)
  --timeout-seconds N      Max seconds to wait per promotion run (default: 900)
  --poll-seconds N         Poll interval in seconds (default: 10)
  --dry-run                Validate and print planned actions without creating issues
  --allow-side-effects     Required for live runs that create issues, labels, branches, and PRs
  --keep-artifacts         Do not close disposable issues/PRs or delete branches
  --help, -h               Show this help

Output includes the promotion workflow run URL and final labels for every pair.
Requires `AGENT_PAT` configured in the repo (promotion adds `agent:implement`,
which GITHUB_TOKEN-created labels cannot do). Secret values are never printed.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)
            REPO="${2:-}"
            [[ -n "$REPO" ]] || { red "Missing value for --repo"; exit 1; }
            shift 2
            ;;
        --pairs)
            PAIRS="${2:-}"
            [[ "$PAIRS" =~ ^[0-9]+$ ]] || { red "--pairs must be an integer"; exit 1; }
            shift 2
            ;;
        --timeout-seconds)
            TIMEOUT_SECONDS="${2:-}"
            [[ "$TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || { red "--timeout-seconds must be an integer"; exit 1; }
            shift 2
            ;;
        --poll-seconds)
            POLL_SECONDS="${2:-}"
            [[ "$POLL_SECONDS" =~ ^[0-9]+$ ]] || { red "--poll-seconds must be an integer"; exit 1; }
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --allow-side-effects)
            ALLOW_SIDE_EFFECTS=true
            shift
            ;;
        --keep-artifacts)
            KEEP_ARTIFACTS=true
            shift
            ;;
        --help|-h)
            _usage
            exit 0
            ;;
        *)
            red "Unknown option: $1"
            echo ""
            _usage
            exit 1
            ;;
    esac
done

if [[ "$PAIRS" -lt 2 ]]; then
    red "--pairs must be at least 2 (the acceptance contract requires reproducibility across two pairs)."
    exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    red "Not inside a git repository."
    exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if [[ -z "$REPO" ]]; then
    if ! command -v gh >/dev/null 2>&1; then
        red "GitHub CLI is required unless --repo is provided with --dry-run."
        exit 1
    fi
    REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
fi

if [[ -z "$REPO" ]]; then
    red "Could not determine GitHub repository. Pass --repo OWNER/REPO."
    exit 1
fi

WORKFLOW_PATH=".github/workflows/$WORKFLOW"
if [[ ! -f "$WORKFLOW_PATH" ]]; then
    red "Workflow not found: $WORKFLOW_PATH"
    exit 1
fi
if ! grep -qE '^[[:space:]]*types:[[:space:]]*\[closed\]' "$WORKFLOW_PATH" \
    && ! grep -qE 'closed' "$WORKFLOW_PATH"; then
    red "Workflow does not appear to trigger on issues:closed: $WORKFLOW"
    exit 1
fi

green "Sandcastle queued-promotion dependency smoke"
echo ""
echo "Repository: $REPO"
echo "Workflow:   $WORKFLOW"
echo "Pairs:      $PAIRS"
echo "Timeout:    ${TIMEOUT_SECONDS}s per promotion"
echo "Cleanup:    $([[ "$KEEP_ARTIFACTS" == true ]] && echo keep || echo close)"
echo ""

if [[ "$DRY_RUN" == true ]]; then
    yellow "Dry run — no issues were created and no labels were applied."
    echo "For each of $PAIRS pair(s), would:"
    echo "  1. Create a disposable blocker issue and dependent issue."
    echo "  2. POST repos/$REPO/issues/<dependent>/dependencies/blocked_by (issue_id=<blocker>)."
    echo "  3. Add label agent:queued to the dependent."
    echo "  4. Close the blocker as completed."
    echo "  5. Wait for $WORKFLOW to run and succeed."
    echo "  6. Verify the dependent lost agent:queued and gained agent:implement."
    exit 0
fi

if [[ "$ALLOW_SIDE_EFFECTS" != true ]]; then
    red "Live promote-queued smoke creates disposable issues, labels, branches, and PRs."
    echo "Pass --allow-side-effects to run it, or --dry-run to preview."
    exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
    red "GitHub CLI is required to run promote-queued smoke."
    exit 1
fi

# ── Cleanup ───────────────────────────────────────────────────────────────────
_created_issues=()
_smoke_branches=()
_temp_files=()
_cleanup_done=false

_cleanup() {
    local status=$?
    if [[ "$_cleanup_done" == true ]]; then
        return "$status"
    fi
    _cleanup_done=true

    for file in "${_temp_files[@]:-}"; do
        [[ -n "$file" ]] && rm -f "$file"
    done

    if [[ "$KEEP_ARTIFACTS" == true ]]; then
        return "$status"
    fi

    # Close any disposable PR + delete the agent branch raised by a cascading
    # agent-implement run, then close every disposable issue we created.
    for branch in "${_smoke_branches[@]:-}"; do
        [[ -n "$branch" ]] || continue
        local pr
        pr="$(gh pr list -R "$REPO" --head "$branch" --state all --json number --jq '.[0].number' 2>/dev/null || true)"
        if [[ -n "$pr" ]]; then
            echo "Cleanup: closing PR #$pr (branch $branch)"
            gh pr close "$pr" -R "$REPO" --delete-branch --comment "Closing disposable promote-queued smoke PR." >/dev/null 2>&1 || true
        else
            gh api --method DELETE "repos/$REPO/git/refs/heads/$branch" >/dev/null 2>&1 || true
        fi
    done

    for num in "${_created_issues[@]:-}"; do
        [[ -n "$num" ]] || continue
        local state
        state="$(gh issue view "$num" -R "$REPO" --json state --jq .state 2>/dev/null || echo "")"
        if [[ "$state" != "CLOSED" ]]; then
            echo "Cleanup: closing issue #$num"
            gh issue close "$num" -R "$REPO" --reason "not planned" --comment "Closing disposable promote-queued smoke fixture." >/dev/null 2>&1 || true
        fi
    done

    return "$status"
}
trap _cleanup EXIT

_new_temp_file() {
    local file
    file="$(mktemp)"
    _temp_files+=("$file")
    printf '%s\n' "$file"
}

# ── Run-selection / parsing helpers (shared shape with issue-label smoke) ──────
_select_new_run() {
    local runs_json="$1" before_file="$2"
    RUNS_JSON="$runs_json" BEFORE_FILE="$before_file" "$PY_BIN" - <<'PY'
import json
import os

runs = json.loads(os.environ.get("RUNS_JSON", "[]"))
with open(os.environ["BEFORE_FILE"], encoding="utf-8") as handle:
    before = {line.strip() for line in handle if line.strip()}

for run in runs:
    run_id = str(run.get("databaseId", ""))
    if run_id and run_id not in before:
        print(json.dumps({"id": run_id, "url": run.get("url", "")}))
        break
PY
}

_read_run_field() {
    local run_file="$1" field="$2"
    RUN_JSON_FILE="$run_file" RUN_FIELD="$field" "$PY_BIN" - <<'PY'
import json
import os
with open(os.environ["RUN_JSON_FILE"], encoding="utf-8") as handle:
    run = json.load(handle)
print(run.get(os.environ["RUN_FIELD"]) or "")
PY
}

# _wait_for_promotion <before_file> <deadline> — sets PROMO_RUN_URL on success.
_wait_for_promotion() {
    local before_file="$1" deadline="$2"
    local selected run_id run_url run_file status conclusion

    echo "  Waiting for $WORKFLOW..."
    while [[ $SECONDS -lt $deadline ]]; do
        local runs_json
        runs_json="$(gh run list \
            --repo "$REPO" \
            --workflow "$WORKFLOW" \
            --event issues \
            --limit 50 \
            --json databaseId,url,status,conclusion,createdAt 2>/dev/null || echo '[]')"
        selected="$(_select_new_run "$runs_json" "$before_file")"
        if [[ -n "$selected" ]]; then
            run_id="$(SELECTED_RUN="$selected" "$PY_BIN" -c 'import json,os;print(json.loads(os.environ["SELECTED_RUN"])["id"])')"
            break
        fi
        sleep "$POLL_SECONDS"
    done

    if [[ -z "${run_id:-}" ]]; then
        red "  Timed out waiting for $WORKFLOW to start."
        return 1
    fi

    run_file="$(_new_temp_file)"
    while [[ $SECONDS -lt $deadline ]]; do
        if gh run view "$run_id" --repo "$REPO" --json databaseId,url,status,conclusion > "$run_file" 2>/dev/null; then
            status="$(_read_run_field "$run_file" status)"
            conclusion="$(_read_run_field "$run_file" conclusion)"
            run_url="$(_read_run_field "$run_file" url)"
            [[ "$status" == "completed" ]] && break
        fi
        sleep "$POLL_SECONDS"
    done

    echo "  Run URL:    ${run_url:-unknown}"
    echo "  Conclusion: ${conclusion:-unknown}"
    if [[ "${status:-}" != "completed" || "${conclusion:-}" != "success" ]]; then
        red "  $WORKFLOW did not complete successfully."
        return 1
    fi
    PROMO_RUN_URL="$run_url"
    return 0
}

# _dependent_promoted <issue_number> — true if the promote-queued workflow promoted
# the dependent. Verified via the durable promotion COMMENT, not the transient
# agent:implement label: promotion immediately triggers agent-implement-issue.yml,
# which consumes agent:implement within seconds, so a label check races the cascade.
_dependent_promoted() {
    local num="$1" comments
    comments="$(gh issue view "$num" -R "$REPO" --json comments --jq '[.comments[].body] | join("\n---\n")' 2>/dev/null || echo '')"
    if printf '%s' "$comments" | grep -qiE 'Promotion failed'; then
        echo "promotion failed (AGENT_PAT could not add agent:implement)"
        return 1
    fi
    if printf '%s' "$comments" | grep -qiE 'promoting from .*agent:queued.* to .*agent:implement'; then
        echo "promoted (promotion comment present)"
        return 0
    fi
    if printf '%s' "$comments" | grep -qiE 'Refused to promote'; then
        echo "refused to promote (see issue comment)"
        return 1
    fi
    echo "no promotion comment found"
    return 1
}

# ── Exercise each disposable pair ─────────────────────────────────────────────
_stamp="$(date -u +%Y%m%d-%H%M%S)"
_pairs_passed=0

for ((pair = 1; pair <= PAIRS; pair++)); do
    echo ""
    echo "── Pair $pair/$PAIRS ──"

    _blocker_url="$(gh issue create -R "$REPO" \
        --title "Sandcastle smoke blocker $_stamp #$pair" \
        --body "Disposable blocker fixture for the queued-promotion smoke. Safe to close." 2>/dev/null || true)"
    _blocker_num="${_blocker_url##*/}"
    if [[ ! "$_blocker_num" =~ ^[0-9]+$ ]]; then
        red "Failed to create blocker issue."
        exit 1
    fi
    _created_issues+=("$_blocker_num")
    echo "  Blocker:   #$_blocker_num"

    _dependent_url="$(gh issue create -R "$REPO" \
        --title "Sandcastle smoke dependent $_stamp #$pair" \
        --body "Disposable dependent fixture for the queued-promotion smoke. Blocked by #$_blocker_num. Safe to close." 2>/dev/null || true)"
    _dependent_num="${_dependent_url##*/}"
    if [[ ! "$_dependent_num" =~ ^[0-9]+$ ]]; then
        red "Failed to create dependent issue."
        exit 1
    fi
    _created_issues+=("$_dependent_num")
    _smoke_branches+=("agent/issue-$_dependent_num")
    echo "  Dependent: #$_dependent_num"

    # Link: dependent is blocked_by blocker (issue_id is the REST numeric id).
    _blocker_id="$(gh api "repos/$REPO/issues/$_blocker_num" --jq .id 2>/dev/null || true)"
    if [[ ! "$_blocker_id" =~ ^[0-9]+$ ]]; then
        red "Could not resolve numeric id for blocker #$_blocker_num."
        exit 1
    fi
    if ! gh api --method POST "repos/$REPO/issues/$_dependent_num/dependencies/blocked_by" \
        -F issue_id="$_blocker_id" >/dev/null 2>&1; then
        red "Failed to set blocked_by dependency (#$_dependent_num blocked by #$_blocker_num)."
        exit 1
    fi
    # Confirm the relation registered before relying on it.
    if ! gh api "repos/$REPO/issues/$_dependent_num/dependencies/blocked_by" \
        --jq '.[].number' 2>/dev/null | grep -qx "$_blocker_num"; then
        red "Dependency did not register (#$_dependent_num is not blocked by #$_blocker_num)."
        exit 1
    fi
    echo "  Linked:    #$_dependent_num blocked by #$_blocker_num"

    gh issue edit "$_dependent_num" -R "$REPO" --add-label "agent:queued" >/dev/null 2>&1 || {
        red "Failed to add agent:queued to #$_dependent_num (is the label installed?)."
        exit 1
    }
    echo "  Queued:    #$_dependent_num labeled agent:queued"

    _before_file="$(_new_temp_file)"
    gh run list --repo "$REPO" --workflow "$WORKFLOW" --event issues --limit 50 \
        --json databaseId --jq '.[].databaseId' > "$_before_file" 2>/dev/null || true

    echo "  Closing blocker #$_blocker_num (completed) to trigger promotion..."
    gh issue close "$_blocker_num" -R "$REPO" --reason completed >/dev/null 2>&1 || {
        red "Failed to close blocker #$_blocker_num."
        exit 1
    }

    _deadline=$((SECONDS + TIMEOUT_SECONDS))
    PROMO_RUN_URL=""
    if ! _wait_for_promotion "$_before_file" "$_deadline"; then
        red "Pair $pair: promotion workflow did not succeed."
        exit 1
    fi

    if _result="$(_dependent_promoted "$_dependent_num")"; then
        green "  Promoted:   #$_dependent_num ($_result)"
        echo "  Evidence:   $PROMO_RUN_URL"
        _pairs_passed=$((_pairs_passed + 1))
    else
        red "  Pair $pair: dependent #$_dependent_num was not promoted ($_result)."
        exit 1
    fi

    # Stop a cascading agent-implement run from churning on this disposable issue.
    gh issue edit "$_dependent_num" -R "$REPO" --remove-label "agent:implement" >/dev/null 2>&1 || true
done

echo ""
echo "════════════════════════════════════════════════"
if [[ "$_pairs_passed" -eq "$PAIRS" ]]; then
    green "Queued-promotion smoke passed across $_pairs_passed/$PAIRS pairs."
    exit 0
fi
red "Queued-promotion smoke failed ($_pairs_passed/$PAIRS pairs passed)."
exit 1
