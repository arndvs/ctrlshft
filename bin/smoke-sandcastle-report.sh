#!/usr/bin/env bash
# smoke-sandcastle-report.sh — Aggregate Sandcastle smoke outcomes into a
# unified JSON + markdown report.
#
# Queries the last N workflow runs for each Sandcastle-related workflow and
# produces a JSON report + markdown summary with pass/fail/skip counts,
# per-workflow coverage, and run URLs.
#
# Usage: ctrl smoke-sandcastle-report [--repo OWNER/REPO] [--limit N] [--json] [--md]
#
# Outputs:
#   --json  Print JSON report to stdout (default if neither flag given)
#   --md    Print markdown report to stdout
#   Both flags print JSON then markdown separated by a blank line.
#
# In CI (GITHUB_STEP_SUMMARY set), also appends the markdown to the step summary.

set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
source "$DOTFILES/bin/_lib.sh"

REPO=""
LIMIT=5
OUTPUT_JSON=false
OUTPUT_MD=false

if command -v python3 >/dev/null 2>&1; then
    PY_BIN=python3
elif command -v python >/dev/null 2>&1; then
    PY_BIN=python
else
    echo "Python is required for report generation." >&2
    exit 1
fi

usage() {
    cat <<'EOF'
Usage: ctrl smoke-sandcastle-report [OPTIONS]

Options:
  --repo OWNER/REPO   Target repository (default: auto-detect from git remote)
  --limit N            Number of recent runs per workflow to inspect (default: 5)
  --json               Output JSON report
  --md                 Output markdown report
  -h, --help           Show this help

If neither --json nor --md is given, both are printed.
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)   REPO="$2"; shift 2 ;;
        --limit)  LIMIT="$2"; shift 2 ;;
        --json)   OUTPUT_JSON=true; shift ;;
        --md)     OUTPUT_MD=true; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ "$OUTPUT_JSON" == "false" && "$OUTPUT_MD" == "false" ]]; then
    OUTPUT_JSON=true
    OUTPUT_MD=true
fi

if [[ -z "$REPO" ]]; then
    REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
    if [[ -z "$REPO" ]]; then
        red "Cannot detect repository. Pass --repo OWNER/REPO."
        exit 1
    fi
fi

# ── Workflow inventory ────────────────────────────────────────────────────────
# All Sandcastle-related workflows that should be covered by smoke tests.
SANDCASTLE_WORKFLOWS=(
    "Agent: Architecture Review"
    "Agent: Check Stale PRs"
    "Agent: Fix PR Feedback"
    "Agent: Implement Issue"
    "Agent: Implement PRD"
    "Agent: Keep Tests Tight"
    "Agent: Merge PR"
    "Agent: Plan Issue"
    "Agent: Promote Queued"
    "Agent: Repo Hygiene"
    "Agent: Review Issue"
    "Agent: Update Branch"
    "Bridge Tests"
    "Integrity"
    "Labels: Sync"
    "PR: request Copilot review"
    "Sandcastle CI"
)

# Smoke scripts that correspond to workflow coverage areas
SMOKE_SCRIPTS=(
    "bin/smoke-sandcastle-dispatch.sh"
    "bin/smoke-sandcastle-issue-labels.sh"
    "bin/smoke-sandcastle-pr-path.sh"
    "bin/smoke-sandcastle-promote-queued.sh"
    "bin/smoke-sandcastle-scheduled.sh"
)

# ── Query workflow runs ───────────────────────────────────────────────────────

_tmpdir="$(mktemp -d)"
trap 'rm -rf "$_tmpdir"' EXIT

_query_workflow_runs() {
    local workflow_name="$1"
    local outfile="$_tmpdir/$(echo "$workflow_name" | tr ' :' '__').json"

    gh run list \
        --repo "$REPO" \
        --workflow "$workflow_name" \
        --limit "$LIMIT" \
        --json databaseId,url,status,conclusion,createdAt,displayTitle,event \
        2>/dev/null > "$outfile" || echo "[]" > "$outfile"

    echo "$outfile"
}

# Query all workflows
declare -A WORKFLOW_FILES
for wf in "${SANDCASTLE_WORKFLOWS[@]}"; do
    WORKFLOW_FILES["$wf"]="$(_query_workflow_runs "$wf")"
done

# ── Generate report ───────────────────────────────────────────────────────────

_report_json="$_tmpdir/report.json"
_report_md="$_tmpdir/report.md"

# Pass data to Python for aggregation
_workflow_data="$_tmpdir/workflow_data.json"
echo "{" > "$_workflow_data"
_first=true
for wf in "${SANDCASTLE_WORKFLOWS[@]}"; do
    _file="${WORKFLOW_FILES[$wf]}"
    if [[ "$_first" == "true" ]]; then
        _first=false
    else
        echo "," >> "$_workflow_data"
    fi
    printf '  %s: ' "$(echo "$wf" | "$PY_BIN" -c 'import json,sys;print(json.dumps(sys.stdin.read().strip()))')" >> "$_workflow_data"
    cat "$_file" >> "$_workflow_data"
done
echo "}" >> "$_workflow_data"

# Build smoke script list
_smoke_list="$_tmpdir/smoke_scripts.json"
echo "[" > "$_smoke_list"
_first=true
for s in "${SMOKE_SCRIPTS[@]}"; do
    if [[ "$_first" == "true" ]]; then _first=false; else echo "," >> "$_smoke_list"; fi
    printf '  %s' "$(echo "$s" | "$PY_BIN" -c 'import json,sys;print(json.dumps(sys.stdin.read().strip()))')" >> "$_smoke_list"
done
echo "]" >> "$_smoke_list"

WORKFLOW_DATA_FILE="$_workflow_data" \
SMOKE_SCRIPTS_FILE="$_smoke_list" \
REPORT_JSON_FILE="$_report_json" \
REPORT_MD_FILE="$_report_md" \
REPO="$REPO" \
"$PY_BIN" - <<'PYEOF'
import json
import os
from datetime import datetime, timezone

workflow_data_file = os.environ["WORKFLOW_DATA_FILE"]
smoke_scripts_file = os.environ["SMOKE_SCRIPTS_FILE"]
report_json_file = os.environ["REPORT_JSON_FILE"]
report_md_file = os.environ["REPORT_MD_FILE"]
repo = os.environ["REPO"]

with open(workflow_data_file, encoding="utf-8") as fh:
    workflow_data = json.load(fh)

with open(smoke_scripts_file, encoding="utf-8") as fh:
    smoke_scripts = json.load(fh)

# Build per-workflow summary
workflows = []
total_pass = 0
total_fail = 0
total_skip = 0
total_workflows = len(workflow_data)
covered_workflows = 0

for name, runs in workflow_data.items():
    if not runs:
        workflows.append({
            "name": name,
            "runs": 0,
            "latest_conclusion": None,
            "latest_url": None,
            "latest_date": None,
            "pass": 0,
            "fail": 0,
            "skip": 0,
        })
        total_skip += 1
        continue

    covered_workflows += 1
    w_pass = sum(1 for r in runs if r.get("conclusion") == "success")
    w_fail = sum(1 for r in runs if r.get("conclusion") in ("failure", "timed_out", "cancelled"))
    w_skip = sum(1 for r in runs if r.get("conclusion") in ("skipped", None, ""))

    latest = runs[0] if runs else {}
    workflows.append({
        "name": name,
        "runs": len(runs),
        "latest_conclusion": latest.get("conclusion") or "unknown",
        "latest_url": latest.get("url") or "",
        "latest_date": latest.get("createdAt") or "",
        "pass": w_pass,
        "fail": w_fail,
        "skip": w_skip,
    })

    total_pass += w_pass
    total_fail += w_fail
    total_skip += w_skip

coverage_pct = round(covered_workflows / total_workflows * 100, 1) if total_workflows else 0

report = {
    "repo": repo,
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "summary": {
        "total_workflows": total_workflows,
        "covered_workflows": covered_workflows,
        "coverage_pct": coverage_pct,
        "total_runs_inspected": total_pass + total_fail + total_skip,
        "pass": total_pass,
        "fail": total_fail,
        "skip": total_skip,
    },
    "smoke_scripts": smoke_scripts,
    "workflows": workflows,
}

with open(report_json_file, "w", encoding="utf-8") as fh:
    json.dump(report, fh, indent=2)

# Build markdown
lines = []
lines.append("# Sandcastle Smoke Report")
lines.append("")
lines.append(f"**Repository:** `{repo}`")
lines.append(f"**Generated:** {report['generated_at']}")
lines.append("")
lines.append("## Summary")
lines.append("")
lines.append(f"| Metric | Value |")
lines.append(f"|--------|-------|")
lines.append(f"| Workflows tracked | {total_workflows} |")
lines.append(f"| Workflows with runs | {covered_workflows} |")
lines.append(f"| Coverage | {coverage_pct}% |")
lines.append(f"| Total runs inspected | {total_pass + total_fail + total_skip} |")
lines.append(f"| Pass | {total_pass} |")
lines.append(f"| Fail | {total_fail} |")
lines.append(f"| Skip/No-run | {total_skip} |")
lines.append("")
lines.append("## Per-Workflow Results")
lines.append("")
lines.append("| Workflow | Runs | Pass | Fail | Skip | Latest | Conclusion |")
lines.append("|----------|------|------|------|------|--------|------------|")

for w in workflows:
    latest_link = ""
    if w["latest_url"]:
        latest_link = f"[{w['latest_date'][:10] if w['latest_date'] else 'N/A'}]({w['latest_url']})"
    elif w["latest_date"]:
        latest_link = w["latest_date"][:10]
    else:
        latest_link = "—"

    conclusion = w.get("latest_conclusion") or "—"
    icon = {"success": "✅", "failure": "❌", "skipped": "⏭️"}.get(conclusion, "—")

    lines.append(
        f"| {w['name']} | {w['runs']} | {w['pass']} | {w['fail']} | {w['skip']} "
        f"| {latest_link} | {icon} {conclusion} |"
    )

lines.append("")
lines.append("## Smoke Scripts")
lines.append("")
for s in smoke_scripts:
    lines.append(f"- `{s}`")
lines.append("")

with open(report_md_file, "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines))
PYEOF

# ── Output ────────────────────────────────────────────────────────────────────

if [[ "$OUTPUT_JSON" == "true" ]]; then
    cat "$_report_json"
fi

if [[ "$OUTPUT_JSON" == "true" && "$OUTPUT_MD" == "true" ]]; then
    echo ""
fi

if [[ "$OUTPUT_MD" == "true" ]]; then
    cat "$_report_md"
fi

# Append to GitHub Step Summary if in CI
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    cat "$_report_md" >> "$GITHUB_STEP_SUMMARY"
fi

# Upload JSON as artifact hint
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "report_json=$_report_json" >> "$GITHUB_OUTPUT"
fi
