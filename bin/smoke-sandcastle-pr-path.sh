#!/usr/bin/env bash
# smoke-sandcastle-pr-path.sh — Drive the Sandcastle PR-path state machine smoke.
#
# Creates a disposable same-repository pull request and walks it through the
# label-driven PR automations:
#   - agent:update-branch -> agent-update-branch.yml
#   - agent:fix           -> agent-fix-pr-feedback.yml
#   - agent:merge         -> agent-merge-pr.yml   (ONLY with --confirm-merge)
#
# Each path is "proven green" when its workflow run completes with conclusion
# success. The merge path is destructive (it merges the PR) and therefore runs
# only under explicit human confirmation, per the slice contract.
#
# The PR is created hermetically through the GitHub API (no local commits, so the
# repo's slow pre-commit hook is never triggered) and cleaned up afterwards.
#
# Usage: ctrl smoke-sandcastle-pr-path --allow-side-effects [--confirm-merge]

set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
source "$DOTFILES/bin/_lib.sh"

REPO=""
BASE=""
TIMEOUT_SECONDS=1800
POLL_SECONDS=10
DRY_RUN=false
ALLOW_SIDE_EFFECTS=false
CONFIRM_MERGE=false
KEEP_ARTIFACTS=false

if command -v python3 >/dev/null 2>&1; then
    PY_BIN=python3
elif command -v python >/dev/null 2>&1; then
    PY_BIN=python
else
    echo "Python is required for Sandcastle PR-path smoke parsing." >&2
    exit 1
fi

_usage() {
    cat <<'EOF'
Usage: ctrl smoke-sandcastle-pr-path [options]

Creates a disposable same-repository PR and proves the update-branch and
fix-pr-feedback automations green by labeling the PR and verifying each
workflow run succeeds. The merge path runs only with explicit --confirm-merge.

Options:
  --repo OWNER/REPO        GitHub repo slug (default: gh repo view)
  --base BRANCH            Base branch for the disposable PR (default: sandcastle.config baseBranch, then dev)
  --timeout-seconds N      Max seconds to wait per workflow run (default: 1800)
  --poll-seconds N         Poll interval in seconds (default: 10)
  --confirm-merge          Also exercise the agent:merge path (MERGES the disposable PR)
  --dry-run                Validate and print planned actions without creating a PR
  --allow-side-effects     Required for live runs (creates a branch, PR, comments, labels)
  --keep-artifacts         Do not close the disposable PR or delete its branch
  --help, -h               Show this help

The update-branch and fix-pr-feedback workflows execute agent code and require
the hosted Copilot proxy to be reachable from Actions. Secret values are never
printed.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)
            REPO="${2:-}"; [[ -n "$REPO" ]] || { red "Missing value for --repo"; exit 1; }; shift 2 ;;
        --base)
            BASE="${2:-}"; [[ -n "$BASE" ]] || { red "Missing value for --base"; exit 1; }; shift 2 ;;
        --timeout-seconds)
            TIMEOUT_SECONDS="${2:-}"; [[ "$TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || { red "--timeout-seconds must be an integer"; exit 1; }; shift 2 ;;
        --poll-seconds)
            POLL_SECONDS="${2:-}"; [[ "$POLL_SECONDS" =~ ^[0-9]+$ ]] || { red "--poll-seconds must be an integer"; exit 1; }; shift 2 ;;
        --confirm-merge)
            CONFIRM_MERGE=true; shift ;;
        --dry-run)
            DRY_RUN=true; shift ;;
        --allow-side-effects)
            ALLOW_SIDE_EFFECTS=true; shift ;;
        --keep-artifacts)
            KEEP_ARTIFACTS=true; shift ;;
        --help|-h)
            _usage; exit 0 ;;
        *)
            red "Unknown option: $1"; echo ""; _usage; exit 1 ;;
    esac
done

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
[[ -n "$REPO" ]] || { red "Could not determine GitHub repository. Pass --repo OWNER/REPO."; exit 1; }

if [[ -z "$BASE" ]]; then
    if [[ -f sandcastle.config.json ]] && command -v node >/dev/null 2>&1; then
        BASE="$(node -e "const fs=require('fs');try{const c=JSON.parse(fs.readFileSync('sandcastle.config.json','utf8'));process.stdout.write(String(c.baseBranch||''))}catch(e){}" 2>/dev/null || true)"
    fi
    BASE="${BASE:-dev}"
fi

# Required workflows must be present and label-triggered.
for _wf_file in agent-update-branch.yml agent-fix-pr-feedback.yml agent-merge-pr.yml; do
    _wf=".github/workflows/$_wf_file"
    [[ -f "$_wf" ]] || { red "Workflow not found: $_wf"; exit 1; }
    grep -q 'pull_request_target:' "$_wf" || { red "Workflow is not pull_request_target-triggered: $_wf"; exit 1; }
done

STAMP="$(date -u +%Y%m%d-%H%M%S)"
BRANCH="sandcastle-smoke/pr-path-$STAMP"
FIXTURE_PATH=".sandcastle-smoke/pr-path-$STAMP.md"

_paths=(agent:update-branch agent:fix)
$CONFIRM_MERGE && _paths+=(agent:merge)

green "Sandcastle PR-path state-machine smoke"
echo ""
echo "Repository:  $REPO"
echo "Base:        $BASE"
echo "Paths:       ${_paths[*]}"
echo "Merge:       $([[ "$CONFIRM_MERGE" == true ]] && echo "ENABLED (--confirm-merge)" || echo "skipped (no --confirm-merge)")"
echo "Cleanup:     $([[ "$KEEP_ARTIFACTS" == true ]] && echo keep || echo close)"
echo ""

if [[ "$DRY_RUN" == true ]]; then
    yellow "Dry run — no branch, PR, labels, or comments were created."
    echo "Would create branch $BRANCH off $BASE with a disposable fixture file, open a same-repo PR, then:"
    echo "  1. label agent:update-branch  -> wait for agent-update-branch.yml -> require success"
    echo "  2. add a review-feedback comment, label agent:fix -> wait for agent-fix-pr-feedback.yml -> require success"
    if $CONFIRM_MERGE; then
        echo "  3. label agent:merge -> wait for agent-merge-pr.yml -> require success + PR merged"
    else
        echo "  (merge path skipped — pass --confirm-merge to exercise it)"
    fi
    echo "Then close the PR and delete the branch."
    exit 0
fi

if [[ "$ALLOW_SIDE_EFFECTS" != true ]]; then
    red "Live PR-path smoke creates a disposable branch, PR, comments, and labels."
    echo "Pass --allow-side-effects to run it, or --dry-run to preview."
    exit 1
fi
command -v gh >/dev/null 2>&1 || { red "GitHub CLI is required to run PR-path smoke."; exit 1; }

# ── Cleanup ───────────────────────────────────────────────────────────────────
_pr_number=""
_pr_merged=false
_branch_created=false
_temp_files=()
_cleanup_done=false

_cleanup() {
    local status=$?
    [[ "$_cleanup_done" == true ]] && return "$status"
    _cleanup_done=true
    for f in "${_temp_files[@]:-}"; do [[ -n "$f" ]] && rm -f "$f"; done
    [[ "$KEEP_ARTIFACTS" == true ]] && return "$status"

    if [[ -n "$_pr_number" && "$_pr_merged" != true ]]; then
        echo "Cleanup: closing PR #$_pr_number"
        gh pr close "$_pr_number" -R "$REPO" --comment "Closing disposable PR-path smoke fixture." >/dev/null 2>&1 || true
    fi
    if [[ "$_branch_created" == true ]]; then
        echo "Cleanup: deleting branch $BRANCH"
        gh api --method DELETE "repos/$REPO/git/refs/heads/$BRANCH" >/dev/null 2>&1 || true
    fi
    return "$status"
}
trap _cleanup EXIT

_new_temp_file() { local f; f="$(mktemp)"; _temp_files+=("$f"); printf '%s\n' "$f"; }

_select_new_run() {
    local runs_json="$1" before_file="$2"
    RUNS_JSON="$runs_json" BEFORE_FILE="$before_file" "$PY_BIN" - <<'PY'
import json, os
runs = json.loads(os.environ.get("RUNS_JSON", "[]"))
with open(os.environ["BEFORE_FILE"], encoding="utf-8") as fh:
    before = {l.strip() for l in fh if l.strip()}
for run in runs:
    rid = str(run.get("databaseId", ""))
    if rid and rid not in before:
        print(json.dumps({"id": rid, "url": run.get("url", "")}))
        break
PY
}

_read_run_field() {
    local run_file="$1" field="$2"
    RUN_JSON_FILE="$run_file" RUN_FIELD="$field" "$PY_BIN" - <<'PY'
import json, os
with open(os.environ["RUN_JSON_FILE"], encoding="utf-8") as fh:
    run = json.load(fh)
print(run.get(os.environ["RUN_FIELD"]) or "")
PY
}

# _exercise_path <label> <workflow> — label the PR, wait for the run, require success.
_exercise_path() {
    local label="$1" workflow="$2"
    local before_file selected run_id run_url run_file status conclusion
    echo ""
    echo "── path: $label ($workflow) ──"

    before_file="$(_new_temp_file)"
    gh run list --repo "$REPO" --workflow "$workflow" --event pull_request_target --limit 50 \
        --json databaseId --jq '.[].databaseId' > "$before_file" 2>/dev/null || true

    gh pr edit "$_pr_number" -R "$REPO" --add-label "$label" >/dev/null 2>&1 || {
        red "  Failed to add label $label (is it installed in the repo?)."
        return 1
    }
    echo "  labeled #$_pr_number $label; waiting for $workflow..."

    local deadline=$((SECONDS + TIMEOUT_SECONDS))
    while [[ $SECONDS -lt $deadline ]]; do
        local runs_json
        runs_json="$(gh run list --repo "$REPO" --workflow "$workflow" --event pull_request_target \
            --limit 50 --json databaseId,url,status,conclusion,createdAt 2>/dev/null || echo '[]')"
        selected="$(_select_new_run "$runs_json" "$before_file")"
        if [[ -n "$selected" ]]; then
            run_id="$(SELECTED_RUN="$selected" "$PY_BIN" -c 'import json,os;print(json.loads(os.environ["SELECTED_RUN"])["id"])')"
            break
        fi
        sleep "$POLL_SECONDS"
    done
    if [[ -z "${run_id:-}" ]]; then
        red "  Timed out waiting for $workflow to start."
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
    if [[ "${status:-}" == "completed" && "${conclusion:-}" == "success" ]]; then
        green "  $label path proven green."
        return 0
    fi
    red "  $label path did not succeed."
    return 1
}

# ── Create the disposable same-repo PR (hermetic, via the API) ────────────────
_base_sha="$(gh api "repos/$REPO/git/refs/heads/$BASE" --jq '.object.sha' 2>/dev/null || true)"
[[ -n "$_base_sha" ]] || { red "Could not resolve base branch ref: $BASE"; exit 1; }

if ! gh api --method POST "repos/$REPO/git/refs" -f ref="refs/heads/$BRANCH" -f sha="$_base_sha" >/dev/null 2>&1; then
    red "Failed to create branch $BRANCH."
    exit 1
fi
_branch_created=true

_content_b64="$(printf '%s\n' "# Disposable PR-path smoke fixture

Created by ctrl smoke-sandcastle-pr-path at $STAMP. Safe to delete." | base64 | tr -d '\n')"
if ! gh api --method PUT "repos/$REPO/contents/$FIXTURE_PATH" \
    -f message="chore(smoke): disposable PR-path fixture $STAMP" \
    -f content="$_content_b64" -f branch="$BRANCH" >/dev/null 2>&1; then
    red "Failed to create fixture file on $BRANCH."
    exit 1
fi

_pr_url="$(gh pr create -R "$REPO" --base "$BASE" --head "$BRANCH" \
    --title "Sandcastle PR-path smoke $STAMP" \
    --body "Disposable fixture exercising the update-branch / fix / merge PR automations. Safe to close." 2>/dev/null || true)"
_pr_number="${_pr_url##*/}"
[[ "$_pr_number" =~ ^[0-9]+$ ]] || { red "Failed to open disposable PR."; exit 1; }
echo "Disposable PR: #$_pr_number ($_pr_url)"

# ── Exercise each path ────────────────────────────────────────────────────────
_failures=()

_exercise_path "agent:update-branch" "agent-update-branch.yml" || _failures+=("update-branch")

# Fix path needs actionable feedback to address.
gh pr comment "$_pr_number" -R "$REPO" \
    --body "Smoke feedback: please append a short note to $FIXTURE_PATH confirming the fix path ran." >/dev/null 2>&1 || true
_exercise_path "agent:fix" "agent-fix-pr-feedback.yml" || _failures+=("fix")

if $CONFIRM_MERGE; then
    if _exercise_path "agent:merge" "agent-merge-pr.yml"; then
        _state="$(gh pr view "$_pr_number" -R "$REPO" --json state --jq .state 2>/dev/null || echo '')"
        if [[ "$_state" == "MERGED" ]]; then
            _pr_merged=true
            green "  merge path: PR #$_pr_number is MERGED."
        else
            red "  merge path: workflow succeeded but PR state is $_state (not MERGED)."
            _failures+=("merge")
        fi
    else
        _failures+=("merge")
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════"
if [[ ${#_failures[@]} -eq 0 ]]; then
    green "PR-path smoke passed (${_paths[*]})."
    exit 0
fi
red "PR-path smoke failed: ${_failures[*]}"
exit 1
