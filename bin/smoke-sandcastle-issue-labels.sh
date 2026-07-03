#!/usr/bin/env bash
# smoke-sandcastle-issue-labels.sh — Drive Sandcastle issue-label workflow smoke.
#
# Usage: ctrl smoke-sandcastle-issue-labels --allow-side-effects [--repo OWNER/REPO]

set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
source "$DOTFILES/bin/_lib.sh"

REPO=""
TIMEOUT_SECONDS=1800
POLL_SECONDS=10
DRY_RUN=false
ALLOW_SIDE_EFFECTS=false
KEEP_ARTIFACTS=false
FIXTURE_TITLE=""
FIXTURE_BODY=""

if command -v python3 >/dev/null 2>&1; then
    PY_BIN=python3
elif command -v python >/dev/null 2>&1; then
    PY_BIN=python
else
    echo "Python is required for Sandcastle issue-label smoke parsing." >&2
    exit 1
fi

_usage() {
    cat <<'EOF'
Usage: ctrl smoke-sandcastle-issue-labels [options]

Creates a disposable issue, applies the Sandcastle label, waits for the
review -> plan -> implement issue-label workflow chain, verifies expected labels,
and cleans up disposable issue/PR artifacts.

Options:
  --repo OWNER/REPO        GitHub repo slug (default: gh repo view)
  --timeout-seconds N      Max seconds to wait for the full chain (default: 1800)
  --poll-seconds N         Poll interval in seconds (default: 10)
  --title TEXT             Fixture issue title (default: timestamped smoke title)
  --body TEXT              Fixture issue body (default: smoke-safe PRD body)
  --dry-run                Validate and print planned actions without creating an issue
  --allow-side-effects     Required for live runs that create issues, branches, and PRs
  --keep-artifacts         Do not close the disposable issue/PR or delete the branch
  --help, -h               Show this help

Output includes workflow run URLs, conclusions, final issue labels, created PR,
and cleanup actions. Secret values are never printed.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)
            REPO="${2:-}"
            [[ -n "$REPO" ]] || { red "Missing value for --repo"; exit 1; }
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
        --title)
            FIXTURE_TITLE="${2:-}"
            [[ -n "$FIXTURE_TITLE" ]] || { red "Missing value for --title"; exit 1; }
            shift 2
            ;;
        --body)
            FIXTURE_BODY="${2:-}"
            [[ -n "$FIXTURE_BODY" ]] || { red "Missing value for --body"; exit 1; }
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

if [[ -z "$FIXTURE_TITLE" ]]; then
    FIXTURE_TITLE="Sandcastle smoke fixture: issue label state machine $(date -u +%Y%m%d-%H%M%S)"
fi

if [[ -z "$FIXTURE_BODY" ]]; then
    FIXTURE_BODY="$(cat <<'EOF'
# Sandcastle disposable issue-label smoke fixture

This issue exists only to verify the Sandcastle review -> plan -> implement label state machine.

## Smoke instructions

- Keep changes minimal and disposable.
- Prefer a no-op documentation-only branch if implementation is required.
- Do not touch secrets or production configuration.

## Acceptance Criteria

- [ ] The review workflow runs and transitions labels.
- [ ] The plan workflow runs and transitions labels.
- [ ] The implement workflow runs and opens or reuses a draft PR.
EOF
)"
fi

_required_workflows=(agent-review-issue.yml agent-plan-issue.yml agent-implement-issue.yml)
for workflow in "${_required_workflows[@]}"; do
    if [[ ! -f ".github/workflows/$workflow" ]]; then
        red "Workflow not found: .github/workflows/$workflow"
        exit 1
    fi
    if ! grep -q "types: \[labeled\]" ".github/workflows/$workflow"; then
        red "Workflow is not an issue-label workflow: $workflow"
        exit 1
    fi
done

if ! command -v gh >/dev/null 2>&1; then
    red "GitHub CLI is required to run issue-label smoke."
    exit 1
fi

green "Sandcastle issue-label smoke"
echo ""
echo "Repository: $REPO"
echo "Fixture:   $FIXTURE_TITLE"
echo "Timeout:   ${TIMEOUT_SECONDS}s"
echo "Cleanup:   $([[ \"$KEEP_ARTIFACTS\" == true ]] && echo keep || echo close)"
echo ""

if [[ "$DRY_RUN" == true ]]; then
    yellow "Dry run — no issue was created and no labels were applied."
    echo "Would create disposable issue in $REPO"
    echo "Would apply label: Sandcastle"
    echo "Would wait for workflows: ${_required_workflows[*]}"
    echo "Would verify final label: agent:pr-open"
    exit 0
fi

if [[ "$ALLOW_SIDE_EFFECTS" != true ]]; then
    red "Live issue-label smoke creates disposable issues, labels, branches, and draft PRs."
    echo "Pass --allow-side-effects to run it, or --dry-run to preview."
    exit 1
fi

_issue_number=""
_issue_url=""
_pr_number=""
_pr_url=""
_branch_name=""
_temp_files=()
_cleanup_done=false

_cleanup() {
    local status=$?
    if [[ "$_cleanup_done" == true ]]; then
        return "$status"
    fi
    _cleanup_done=true

    for file in "${_temp_files[@]:-}"; do
        rm -f "$file"
    done

    if [[ "$KEEP_ARTIFACTS" == true ]]; then
        return "$status"
    fi

    if [[ -n "${_pr_number:-}" ]]; then
        echo "Cleanup: closing PR #$_pr_number and deleting branch if possible"
        gh pr close "$_pr_number" -R "$REPO" --delete-branch --comment "Closing disposable Sandcastle smoke PR from issue #$_issue_number." >/dev/null 2>&1 || true
    elif [[ -n "${_branch_name:-}" ]]; then
        echo "Cleanup: deleting branch $_branch_name if it exists"
        gh api --method DELETE "repos/$REPO/git/refs/heads/$_branch_name" >/dev/null 2>&1 || true
    fi

    if [[ -n "${_issue_number:-}" ]]; then
        echo "Cleanup: closing issue #$_issue_number"
        gh issue close "$_issue_number" -R "$REPO" --comment "Closing disposable Sandcastle issue-label smoke fixture." >/dev/null 2>&1 || true
    fi

    return "$status"
}
trap _cleanup EXIT

_new_temp_file() {
    local file
    file="$(mktemp)"
    _temp_files+=("$file")
    printf '%s\n' "$file"
}

_capture_run_ids() {
    local workflow="$1"
    local output_file="$2"
    gh run list \
        --repo "$REPO" \
        --workflow "$workflow" \
        --event issues \
        --limit 50 \
        --json databaseId \
        --jq '.[].databaseId' > "$output_file" 2>/dev/null || true
}

_select_new_run() {
    local runs_json="$1"
    local before_file="$2"
    RUNS_JSON="$runs_json" BEFORE_FILE="$before_file" "$PY_BIN" - <<'PY'
import json
import os

runs = json.loads(os.environ.get("RUNS_JSON", "[]"))
with open(os.environ["BEFORE_FILE"], encoding="utf-8") as handle:
    before = {line.strip() for line in handle if line.strip()}

for run in runs:
    run_id = str(run.get("databaseId", ""))
    if run.get("status") == "completed" and run.get("conclusion") == "skipped":
        continue
    if run_id and run_id not in before:
        print(json.dumps({"id": run_id, "url": run.get("url", "")}))
        break
PY
}

_read_run_field() {
    local run_file="$1"
    local field="$2"
    RUN_JSON_FILE="$run_file" RUN_FIELD="$field" "$PY_BIN" - <<'PY'
import json
import os
with open(os.environ["RUN_JSON_FILE"], encoding="utf-8") as handle:
    run = json.load(handle)
print(run.get(os.environ["RUN_FIELD"]) or "")
PY
}

_failed_steps() {
    local run_file="$1"
    RUN_JSON_FILE="$run_file" "$PY_BIN" - <<'PY'
import json
import os
with open(os.environ["RUN_JSON_FILE"], encoding="utf-8") as handle:
    run = json.load(handle)
failed = []
for job in run.get("jobs") or []:
    job_name = job.get("name") or f"job {job.get('databaseId', '')}".strip()
    for step in job.get("steps") or []:
        conclusion = step.get("conclusion")
        if conclusion in {"failure", "timed_out", "cancelled", "action_required"}:
            failed.append(f"{job_name} / {step.get('name', 'unnamed step')} ({conclusion})")
print("\n".join(failed))
PY
}

_wait_for_workflow() {
    local workflow="$1"
    local before_file="$2"
    local deadline="$3"
    local selected run_id run_url run_file status conclusion failed

    echo "Waiting for $workflow..."
    while [[ $SECONDS -lt $deadline ]]; do
        local runs_json
        runs_json="$(gh run list \
            --repo "$REPO" \
            --workflow "$workflow" \
            --event issues \
            --limit 50 \
            --json databaseId,url,status,conclusion,createdAt,name,displayTitle 2>/dev/null || echo '[]')"
        selected="$(_select_new_run "$runs_json" "$before_file")"
        if [[ -n "$selected" ]]; then
            run_id="$(SELECTED_RUN="$selected" "$PY_BIN" - <<'PY'
import json
import os
print(json.loads(os.environ["SELECTED_RUN"])["id"])
PY
)"
            run_url="$(SELECTED_RUN="$selected" "$PY_BIN" - <<'PY'
import json
import os
print(json.loads(os.environ["SELECTED_RUN"]).get("url") or "")
PY
)"
            break
        fi
        sleep "$POLL_SECONDS"
    done

    if [[ -z "${run_id:-}" ]]; then
        red "Timed out waiting for $workflow to start."
        exit 1
    fi

    echo "  Run ID:  $run_id"
    echo "  Run URL: $run_url"
    run_file="$(_new_temp_file)"

    while [[ $SECONDS -lt $deadline ]]; do
        if gh run view "$run_id" --repo "$REPO" --json databaseId,url,status,conclusion,jobs,name,createdAt,updatedAt > "$run_file" 2>/dev/null; then
            status="$(_read_run_field "$run_file" status)"
            conclusion="$(_read_run_field "$run_file" conclusion)"
            run_url="$(_read_run_field "$run_file" url)"
            if [[ "$status" == "completed" ]]; then
                break
            fi
        fi
        sleep "$POLL_SECONDS"
    done

    if [[ "${status:-}" != "completed" ]]; then
        red "$workflow timed out before completion."
        echo "  Run URL: $run_url"
        echo "  Status:  ${status:-unknown}"
        exit 1
    fi

    failed="$(_failed_steps "$run_file")"
    echo "  Status:     $status"
    echo "  Conclusion: ${conclusion:-unknown}"
    if [[ -n "$failed" ]]; then
        echo "  Failed steps:"
        sed 's/^/    - /' <<<"$failed"
    else
        echo "  Failed steps: none"
    fi

    if [[ "$conclusion" != "success" ]]; then
        red "$workflow did not succeed."
        exit 1
    fi

    echo "RUN_URL=$run_url"
}

_issue_labels_json() {
    gh issue view "$_issue_number" -R "$REPO" --json labels,state --jq '{state, labels: [.labels[].name]}'
}

_assert_final_labels() {
    local labels_json="$1"
    LABELS_JSON="$labels_json" "$PY_BIN" - <<'PY'
import json
import os
import sys
payload = json.loads(os.environ["LABELS_JSON"])
labels = set(payload.get("labels") or [])
required = {"agent:pr-open"}
forbidden = {"Sandcastle", "agent:review", "agent:implement", "agent:in-progress", "agent:blocked"}
missing = sorted(required - labels)
present_forbidden = sorted(forbidden & labels)
if missing or present_forbidden:
    print(json.dumps({"missing": missing, "forbiddenPresent": present_forbidden, "labels": sorted(labels)}, indent=2))
    sys.exit(1)
print(json.dumps({"labels": sorted(labels)}, indent=2))
PY
}

_slugify_title() {
    TITLE="$1" "$PY_BIN" - <<'PY'
import os
import re
title = os.environ["TITLE"].lower()
slug = re.sub(r"[^a-z0-9]+", "-", title).strip("-")[:50]
print(slug)
PY
}

review_before="$(_new_temp_file)"
plan_before="$(_new_temp_file)"
implement_before="$(_new_temp_file)"
_capture_run_ids agent-review-issue.yml "$review_before"
_capture_run_ids agent-plan-issue.yml "$plan_before"
_capture_run_ids agent-implement-issue.yml "$implement_before"

_issue_url="$(gh issue create -R "$REPO" --title "$FIXTURE_TITLE" --body "$FIXTURE_BODY")"
_issue_number="$(ISSUE_URL="$_issue_url" "$PY_BIN" - <<'PY'
import os
import re
match = re.search(r"/(\d+)$", os.environ["ISSUE_URL"].strip())
if not match:
    raise SystemExit(f"Could not parse issue number from {os.environ['ISSUE_URL']!r}")
print(match.group(1))
PY
)"
_branch_name="agent/issue-${_issue_number}-$(_slugify_title "$FIXTURE_TITLE")"

green "Created disposable issue #$_issue_number"
echo "Issue URL: $_issue_url"
echo "Expected branch: $_branch_name"
echo ""

gh issue edit "$_issue_number" -R "$REPO" --add-label Sandcastle >/dev/null
green "Applied Sandcastle label."
echo ""

_deadline=$((SECONDS + TIMEOUT_SECONDS))
review_output="$(_wait_for_workflow agent-review-issue.yml "$review_before" "$_deadline")"
plan_output="$(_wait_for_workflow agent-plan-issue.yml "$plan_before" "$_deadline")"
implement_output="$(_wait_for_workflow agent-implement-issue.yml "$implement_before" "$_deadline")"

echo ""
echo "Final issue label verification:"
labels_json="$(_issue_labels_json)"
if final_label_report="$(_assert_final_labels "$labels_json" 2>&1)"; then
    green "  ✓ Final labels match expected implement terminal state"
    echo "$final_label_report"
else
    red "  ✗ Final labels did not match expected implement terminal state"
    echo "$final_label_report"
    exit 1
fi

pr_json="$(gh pr list -R "$REPO" --head "$_branch_name" --state open --json number,url --jq '.[0] // empty' 2>/dev/null || true)"
if [[ -n "$pr_json" ]]; then
    _pr_number="$(PR_JSON="$pr_json" "$PY_BIN" - <<'PY'
import json
import os
print(json.loads(os.environ["PR_JSON"])["number"])
PY
)"
    _pr_url="$(PR_JSON="$pr_json" "$PY_BIN" - <<'PY'
import json
import os
print(json.loads(os.environ["PR_JSON"]).get("url") or "")
PY
)"
fi

echo ""
green "Issue-label smoke passed."
echo "Issue:       $_issue_url"
echo "$review_output" | grep '^RUN_URL=' | sed 's/^RUN_URL=/Review run:  /'
echo "$plan_output" | grep '^RUN_URL=' | sed 's/^RUN_URL=/Plan run:    /'
echo "$implement_output" | grep '^RUN_URL=' | sed 's/^RUN_URL=/Implement:   /'
if [[ -n "$_pr_url" ]]; then
    echo "Draft PR:    $_pr_url"
else
    yellow "Draft PR:    not found for $_branch_name"
fi

if [[ "$KEEP_ARTIFACTS" == true ]]; then
    yellow "Artifacts kept by request."
else
    echo "Cleanup will close disposable artifacts now."
fi
