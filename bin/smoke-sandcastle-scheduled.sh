#!/usr/bin/env bash
# smoke-sandcastle-scheduled.sh — Exercise schedule-backed Sandcastle workflows
# on-demand (schedule-equivalent) via manual workflow_dispatch, with a
# standardized timeout and retry policy.
#
# A "schedule-backed" workflow is one that declares both a `schedule:` trigger
# and `workflow_dispatch`. Scheduled triggers cannot be fired on demand, so this
# wrapper provides a deterministic way to exercise them in dogfood tests by
# dispatching each one and waiting for completion. Each run delegates to
# smoke-sandcastle-dispatch (the safe dispatch harness) and is clearly marked as
# a schedule-equivalent execution.
#
# Usage: ctrl smoke-sandcastle-scheduled --allow-side-effects [--workflow FILE]

set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
source "$DOTFILES/bin/_lib.sh"

DISPATCH="$DOTFILES/bin/smoke-sandcastle-dispatch.sh"

WORKFLOW=""
REF=""
REPO=""
TIMEOUT_SECONDS=900
POLL_SECONDS=5
RETRIES=1
RETRY_DELAY_SECONDS=15
LIST_ONLY=false
DRY_RUN=false
ALLOW_SIDE_EFFECTS=false

_usage() {
    cat <<'EOF'
Usage: ctrl smoke-sandcastle-scheduled [options]

Exercises schedule-backed Sandcastle workflows (those declaring both a
`schedule:` trigger and `workflow_dispatch`) on-demand — a schedule-equivalent
run — by delegating each dispatch to smoke-sandcastle-dispatch with a
standardized timeout and retry policy. Aggregates pass/fail across every wrapped
workflow.

Options:
  --workflow FILE          Run only this schedule-backed workflow (default: all discovered)
  --ref REF                Git ref to dispatch (default: dispatch harness resolves it)
  --repo OWNER/REPO        GitHub repo slug (default: gh repo view)
  --timeout-seconds N      Per-run completion timeout (default: 900)
  --poll-seconds N         Poll interval in seconds (default: 5)
  --retries N              Retry attempts per workflow after the first failure (default: 1)
  --retry-delay-seconds N  Seconds to wait between retries (default: 15)
  --list                   List discovered schedule-backed workflows and exit
  --dry-run                Print the planned schedule-equivalent dispatches without running them
  --allow-side-effects     Required for live runs (these workflows can create issues or touch PRs)
  --help, -h               Show this help

Every live dispatch is marked as a SCHEDULE-EQUIVALENT run in the output. Live
runs may create issues (for example agent-architecture-review can open a
source:architecture-review issue). Secret values are never printed.
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
        --retries)
            RETRIES="${2:-}"
            [[ "$RETRIES" =~ ^[0-9]+$ ]] || { red "--retries must be an integer"; exit 1; }
            shift 2
            ;;
        --retry-delay-seconds)
            RETRY_DELAY_SECONDS="${2:-}"
            [[ "$RETRY_DELAY_SECONDS" =~ ^[0-9]+$ ]] || { red "--retry-delay-seconds must be an integer"; exit 1; }
            shift 2
            ;;
        --list)
            LIST_ONLY=true
            shift
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

if [[ ! -f "$DISPATCH" ]]; then
    red "Dispatch harness not found: $DISPATCH"
    exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    red "Not inside a git repository."
    exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# ── Discover schedule-backed workflows (declare both schedule: and workflow_dispatch) ──
_scheduled=()
for _wf_path in "$REPO_ROOT"/.github/workflows/*.yml "$REPO_ROOT"/.github/workflows/*.yaml; do
    [[ -f "$_wf_path" ]] || continue
    if grep -qE '^[[:space:]]*schedule:' "$_wf_path" \
        && grep -qE '^[[:space:]]*workflow_dispatch:' "$_wf_path"; then
        _scheduled+=("$(basename "$_wf_path")")
    fi
done

if [[ ${#_scheduled[@]} -eq 0 ]]; then
    red "No schedule-backed workflows found in .github/workflows/."
    echo "  A schedule-backed workflow declares both 'schedule:' and 'workflow_dispatch'."
    exit 1
fi

# Restrict to a single workflow if requested.
if [[ -n "$WORKFLOW" ]]; then
    _found=false
    for _wf in "${_scheduled[@]}"; do
        [[ "$_wf" == "$WORKFLOW" ]] && _found=true
    done
    if [[ "$_found" != true ]]; then
        red "Not a discovered schedule-backed workflow: $WORKFLOW"
        echo "  Discovered: ${_scheduled[*]}"
        exit 1
    fi
    _scheduled=("$WORKFLOW")
fi

green "Sandcastle scheduled-workflow smoke (schedule-equivalent)"
echo ""
echo "Repository:   ${REPO:-<gh repo view>}"
echo "Workflows:    ${_scheduled[*]}"
echo "Timeout/run:  ${TIMEOUT_SECONDS}s"
echo "Retries/run:  ${RETRIES} (delay ${RETRY_DELAY_SECONDS}s)"
echo ""

# Passthrough args for the dispatch harness.
_passthru=(--timeout-seconds "$TIMEOUT_SECONDS" --poll-seconds "$POLL_SECONDS")
[[ -n "$REF" ]] && _passthru+=(--ref "$REF")
[[ -n "$REPO" ]] && _passthru+=(--repo "$REPO")

# ── List / dry-run: handled by the wrapper, never dispatches ──
if [[ "$LIST_ONLY" == true ]]; then
    echo "Discovered schedule-backed workflows:"
    for _wf in "${_scheduled[@]}"; do
        echo "  - $_wf"
    done
    exit 0
fi

if [[ "$DRY_RUN" == true ]]; then
    yellow "Dry run — no workflow was dispatched."
    for _wf in "${_scheduled[@]}"; do
        echo "Would run (schedule-equivalent): smoke-sandcastle-dispatch --workflow $_wf ${_passthru[*]} --allow-side-effects"
    done
    exit 0
fi

# ── Live runs require explicit opt-in (these workflows can mutate state) ──
if [[ "$ALLOW_SIDE_EFFECTS" != true ]]; then
    red "Scheduled-workflow smoke triggers live workflow runs that may create issues or touch PRs."
    echo "Pass --allow-side-effects to run it, --dry-run to preview, or --list to enumerate."
    exit 1
fi

# ── Run each workflow with standardized retry ──
_run_one() {
    local wf="$1"
    local attempt=1
    local max=$((RETRIES + 1))
    while (( attempt <= max )); do
        echo ""
        echo "== SCHEDULE-EQUIVALENT RUN: $wf (attempt ${attempt}/${max}) =="
        if bash "$DISPATCH" --workflow "$wf" "${_passthru[@]}" --allow-side-effects; then
            return 0
        fi
        attempt=$((attempt + 1))
        if (( attempt <= max )); then
            yellow "Run failed. Retrying $wf in ${RETRY_DELAY_SECONDS}s (attempt ${attempt}/${max})..."
            sleep "$RETRY_DELAY_SECONDS"
        fi
    done
    return 1
}

_passed=()
_failed=()
for _wf in "${_scheduled[@]}"; do
    if _run_one "$_wf"; then
        _passed+=("$_wf")
    else
        _failed+=("$_wf")
    fi
done

echo ""
echo "════════════════════════════════════════════════"
green "Passed (${#_passed[@]}): ${_passed[*]:-none}"
if [[ ${#_failed[@]} -gt 0 ]]; then
    red "Failed (${#_failed[@]}): ${_failed[*]}"
    exit 1
fi
green "All schedule-equivalent runs passed."
exit 0
