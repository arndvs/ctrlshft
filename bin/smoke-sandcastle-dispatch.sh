#!/usr/bin/env bash
# smoke-sandcastle-dispatch.sh — Trigger a safe Sandcastle workflow_dispatch smoke run.
#
# Usage: ctrl smoke-sandcastle-dispatch [--workflow agent-check-stale-prs.yml] [--ref dev]

set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
source "$DOTFILES/bin/_lib.sh"

WORKFLOW="agent-check-stale-prs.yml"
REF=""
REPO=""
TIMEOUT_SECONDS=900
POLL_SECONDS=5
DRY_RUN=false
ALLOW_SIDE_EFFECTS=false

if command -v python3 >/dev/null 2>&1; then
    PY_BIN=python3
elif command -v python >/dev/null 2>&1; then
    PY_BIN=python
else
    echo "Python is required for Sandcastle dispatch smoke parsing." >&2
    exit 1
fi

_usage() {
    cat <<'EOF'
Usage: ctrl smoke-sandcastle-dispatch [options]

Triggers one safe Sandcastle workflow_dispatch run and waits for completion.

Options:
  --workflow FILE          Workflow file to dispatch (default: agent-check-stale-prs.yml)
  --ref REF                Git ref to dispatch (default: sandcastle.config.json baseBranch, then current branch)
  --repo OWNER/REPO        GitHub repo slug (default: gh repo view)
  --timeout-seconds N      Max seconds to wait for completion (default: 900)
  --poll-seconds N         Poll interval in seconds (default: 5)
  --dry-run                Validate and print what would dispatch without triggering Actions
  --allow-side-effects     Allow dispatching workflows beyond the safe default allowlist
  --help, -h               Show this help

Output includes the workflow run URL, status, conclusion, and failed step names
when the run does not succeed. Secret values are never printed.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workflow)
            WORKFLOW="${2:-}"
            [[ -n "$WORKFLOW" ]] || { red "Missing value for --workflow"; exit 1; }
            shift 2
            ;;
        --ref)
            REF="${2:-}"
            [[ -n "$REF" ]] || { red "Missing value for --ref"; exit 1; }
            shift 2
            ;;
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
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --allow-side-effects)
            ALLOW_SIDE_EFFECTS=true
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

if [[ -z "$REF" ]]; then
    if [[ -f sandcastle.config.json ]]; then
        REF="$(node -e "const fs=require('fs'); const c=JSON.parse(fs.readFileSync('sandcastle.config.json','utf8')); process.stdout.write(String(c.baseBranch || ''));" 2>/dev/null || true)"
    fi
    REF="${REF:-$(git branch --show-current)}"
fi

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
if ! grep -qE '^  workflow_dispatch:' "$WORKFLOW_PATH"; then
    red "Workflow does not declare workflow_dispatch: $WORKFLOW"
    exit 1
fi

case "$WORKFLOW" in
    agent-check-stale-prs.yml) ;;
    *)
        if [[ "$ALLOW_SIDE_EFFECTS" != true ]]; then
            red "Workflow is not in the safe dispatch allowlist: $WORKFLOW"
            echo "  Safe default: agent-check-stale-prs.yml"
            echo "  Pass --allow-side-effects only for intentionally mutating fixtures."
            exit 1
        fi
        ;;
esac

if ! command -v gh >/dev/null 2>&1; then
    red "GitHub CLI is required to dispatch workflows."
    exit 1
fi

green "Sandcastle dispatch smoke"
echo ""
echo "Repository: $REPO"
echo "Workflow:   $WORKFLOW"
echo "Ref:        $REF"
echo "Timeout:    ${TIMEOUT_SECONDS}s"
echo ""

if [[ "$DRY_RUN" == true ]]; then
    yellow "Dry run — no workflow was dispatched."
    echo "Would run: gh workflow run $WORKFLOW --repo $REPO --ref $REF"
    exit 0
fi

_before_ids="$(gh run list \
    --repo "$REPO" \
    --workflow "$WORKFLOW" \
    --branch "$REF" \
    --event workflow_dispatch \
    --limit 20 \
    --json databaseId \
    --jq '.[].databaseId' 2>/dev/null || true)"

_before_file="$(mktemp)"
printf '%s\n' "$_before_ids" > "$_before_file"
trap 'rm -f "$_before_file" "${_run_json_file:-}"' EXIT

gh workflow run "$WORKFLOW" --repo "$REPO" --ref "$REF" >/dev/null

green "Dispatch requested. Waiting for workflow run..."

_deadline=$((SECONDS + TIMEOUT_SECONDS))
_run_id=""
_run_url=""
_run_json_file="$(mktemp)"

while [[ $SECONDS -lt $_deadline ]]; do
    _runs_json="$(gh run list \
        --repo "$REPO" \
        --workflow "$WORKFLOW" \
        --branch "$REF" \
        --event workflow_dispatch \
        --limit 20 \
        --json databaseId,url,status,conclusion,createdAt,name,displayTitle 2>/dev/null || echo '[]')"

    _selected="$(RUNS_JSON="$_runs_json" BEFORE_FILE="$_before_file" "$PY_BIN" - <<'PY'
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
)"
    if [[ -n "$_selected" ]]; then
    _run_id="$(SELECTED_RUN="$_selected" "$PY_BIN" - <<'PY'
import json
import os
print(json.loads(os.environ["SELECTED_RUN"])["id"])
PY
)"
    _run_url="$(SELECTED_RUN="$_selected" "$PY_BIN" - <<'PY'
import json
import os
print(json.loads(os.environ["SELECTED_RUN"]).get("url") or "")
PY
)"
        break
    fi
    sleep "$POLL_SECONDS"
done

if [[ -z "$_run_id" ]]; then
    red "Timed out waiting for a new workflow_dispatch run to appear."
    exit 1
fi

echo "Run ID:     $_run_id"
[[ -n "$_run_url" ]] && echo "Run URL:    $_run_url"
echo ""

while [[ $SECONDS -lt $_deadline ]]; do
    if gh run view "$_run_id" --repo "$REPO" --json databaseId,url,status,conclusion,jobs,name,createdAt,updatedAt > "$_run_json_file" 2>/dev/null; then
        _status="$(RUN_JSON_FILE="$_run_json_file" "$PY_BIN" - <<'PY'
import json
import os
with open(os.environ["RUN_JSON_FILE"], encoding="utf-8") as handle:
    run = json.load(handle)
print(run.get("status") or "")
PY
)"
        _conclusion="$(RUN_JSON_FILE="$_run_json_file" "$PY_BIN" - <<'PY'
import json
import os
with open(os.environ["RUN_JSON_FILE"], encoding="utf-8") as handle:
    run = json.load(handle)
print(run.get("conclusion") or "")
PY
)"
        _run_url="$(RUN_JSON_FILE="$_run_json_file" "$PY_BIN" - <<'PY'
import json
import os
with open(os.environ["RUN_JSON_FILE"], encoding="utf-8") as handle:
    run = json.load(handle)
print(run.get("url") or "")
PY
)"
        if [[ "$_status" == "completed" ]]; then
            break
        fi
    fi
    sleep "$POLL_SECONDS"
done

if [[ "${_status:-}" != "completed" ]]; then
    red "Timed out waiting for workflow run completion."
    [[ -n "$_run_url" ]] && echo "Run URL:    $_run_url"
    echo "Status:     ${_status:-unknown}"
    exit 1
fi

_failed_steps="$(RUN_JSON_FILE="$_run_json_file" "$PY_BIN" - <<'PY'
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
)"

if [[ "$_conclusion" == "success" ]]; then
    green "Dispatch smoke passed."
else
    red "Dispatch smoke failed."
fi

echo "Run URL:    $_run_url"
echo "Status:     $_status"
echo "Conclusion: ${_conclusion:-unknown}"
if [[ -n "$_failed_steps" ]]; then
    echo "Failed steps:"
    sed 's/^/  - /' <<<"$_failed_steps"
else
    echo "Failed steps: none"
fi

if [[ "$_conclusion" == "success" ]]; then
    exit 0
fi
exit 1
