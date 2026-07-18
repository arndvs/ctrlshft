#!/usr/bin/env bash
# test/sandcastle-smoke-coverage.sh — Verify every Sandcastle workflow has smoke
# test coverage and the report aggregator inventory matches installed workflows.
#
# This is the structural QA gate: it ensures no workflow falls through the cracks
# when new agent workflows are added. It checks:
#   1. Every installed agent workflow is listed in the report aggregator.
#   2. Every agent workflow maps to at least one smoke script or report path.
#   3. The smoke matrix doc exists and references every workflow.
#   4. The nightly cron workflow exists and can exercise the report.
#   5. Agent workflows use the isolated pnpm runner invocation.
#
# Usage: bash test/sandcastle-smoke-coverage.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$ROOT/working/tmp/sandcastle-smoke-coverage-test"

PASS=0
FAIL=0
FAILURES=()

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

_record_pass() {
    local label="$1"
    PASS=$((PASS + 1))
    printf "  \033[32m✓\033[0m %s\n" "$label"
}

_record_fail() {
    local label="$1"
    local detail="$2"
    FAIL=$((FAIL + 1))
    FAILURES+=("$label — $detail")
    printf "  \033[31m✗\033[0m %s — %s\n" "$label" "$detail"
}

echo
echo "Sandcastle smoke coverage verification"
echo "════════════════════════════════════════════════"

rm -rf "$TMP_ROOT"
mkdir -p "$TMP_ROOT"

# ── 1. Installed agent workflows ─────────────────────────────────────────────
# Collect every installed agent-* workflow file.
installed_agent_workflows=()
for wf in "$ROOT"/.github/workflows/agent-*.yml; do
    [[ -f "$wf" ]] || continue
    installed_agent_workflows+=("$(basename "$wf")")
done

if [[ ${#installed_agent_workflows[@]} -ge 10 ]]; then
    _record_pass "at least 10 agent workflows installed (${#installed_agent_workflows[@]})"
else
    _record_fail "at least 10 agent workflows installed" "found ${#installed_agent_workflows[@]}"
fi

# ── 2. Report aggregator inventory completeness ──────────────────────────────
# The report aggregator lists workflows by display name in SANDCASTLE_WORKFLOWS.
# Map each installed agent workflow file to its display name and check presence.
report_script="$ROOT/bin/smoke-sandcastle-report.sh"
if [[ ! -f "$report_script" ]]; then
    _record_fail "report aggregator script exists" "bin/smoke-sandcastle-report.sh not found"
else
    _record_pass "report aggregator script exists"

    # Extract the SANDCASTLE_WORKFLOWS array entries from the report script.
    report_workflows="$TMP_ROOT/report-workflows.txt"
    sed -n '/^SANDCASTLE_WORKFLOWS=(/,/^)$/p' "$report_script" \
        | grep -E '^[[:space:]]+"' \
        | sed 's/^[[:space:]]*"//;s/"$//' > "$report_workflows"

    for wf_file in "${installed_agent_workflows[@]}"; do
        # Derive the expected display name from the workflow file.
        wf_path="$ROOT/.github/workflows/$wf_file"
        display_name="$(grep -E '^name:' "$wf_path" | head -1 | sed 's/^name:[[:space:]]*"//;s/"$//' | sed "s/^name:[[:space:]]*//")"
        # Strip any remaining quotes
        display_name="${display_name//\"/}"

        if grep -qF "$display_name" "$report_workflows"; then
            _record_pass "report tracks $wf_file ($display_name)"
        else
            _record_fail "report tracks $wf_file" "display name '$display_name' not in SANDCASTLE_WORKFLOWS"
        fi
    done
fi

# ── 3. Smoke script coverage per workflow ────────────────────────────────────
# Each agent workflow should be referenced by at least one smoke script or
# covered by the report aggregator's passive query.
smoke_scripts=(
    "$ROOT/bin/smoke-sandcastle-dispatch.sh"
    "$ROOT/bin/smoke-sandcastle-issue-labels.sh"
    "$ROOT/bin/smoke-sandcastle-pr-path.sh"
    "$ROOT/bin/smoke-sandcastle-promote-queued.sh"
    "$ROOT/bin/smoke-sandcastle-scheduled.sh"
    "$ROOT/bin/smoke-sandcastle-report.sh"
)

# Coverage mapping: each workflow needs active coverage (a smoke script that
# directly exercises it) OR passive coverage (the report aggregator queries its
# run history). We track both.
declare -A active_coverage
declare -A passive_coverage

for wf_file in "${installed_agent_workflows[@]}"; do
    wf_stem="${wf_file%.yml}"
    active_coverage[$wf_file]=""
    passive_coverage[$wf_file]=""

    # Check active coverage (smoke scripts that reference this workflow by file name)
    for smoke in "${smoke_scripts[@]}"; do
        [[ -f "$smoke" ]] || continue
        smoke_base="$(basename "$smoke")"
        if grep -qF "$wf_stem" "$smoke"; then
            active_coverage[$wf_file]="${active_coverage[$wf_file]} $smoke_base"
        fi
    done

    # Passive coverage: the report aggregator queries all 16 workflows by name
    wf_path="$ROOT/.github/workflows/$wf_file"
    display_name="$(grep -E '^name:' "$wf_path" | head -1 | sed 's/^name:[[:space:]]*"//;s/"$//' | sed "s/^name:[[:space:]]*//")"
    display_name="${display_name//\"/}"
    if grep -qF "$display_name" "$report_script" 2>/dev/null; then
        passive_coverage[$wf_file]="smoke-sandcastle-report.sh"
    fi
done

active_count=0
passive_only_count=0
uncovered_count=0
for wf_file in "${installed_agent_workflows[@]}"; do
    active="${active_coverage[$wf_file]:-}"
    passive="${passive_coverage[$wf_file]:-}"

    if [[ -n "$active" ]]; then
        active_count=$((active_count + 1))
        _record_pass "$wf_file has active smoke coverage:${active}"
    elif [[ -n "$passive" ]]; then
        passive_only_count=$((passive_only_count + 1))
        _record_pass "$wf_file has passive report coverage ($passive)"
    else
        uncovered_count=$((uncovered_count + 1))
        _record_fail "$wf_file has smoke coverage" "no active or passive coverage found"
    fi
done

echo ""
echo "  Coverage summary: $active_count active, $passive_only_count passive-only, $uncovered_count uncovered"

# ── 4. Smoke matrix documentation exists ─────────────────────────────────────
matrix_doc="$ROOT/shft/docs/full-smoke-matrix.md"
if [[ -f "$matrix_doc" ]]; then
    _record_pass "full smoke matrix doc exists"

    # Verify matrix references every installed agent workflow
    matrix_missing=()
    for wf_file in "${installed_agent_workflows[@]}"; do
        wf_stem="${wf_file%.yml}"
        if ! grep -qF "$wf_stem" "$matrix_doc"; then
            matrix_missing+=("$wf_stem")
        fi
    done
    if [[ ${#matrix_missing[@]} -eq 0 ]]; then
        _record_pass "smoke matrix references all ${#installed_agent_workflows[@]} agent workflows"
    else
        _record_fail "smoke matrix references all agent workflows" "missing: ${matrix_missing[*]}"
    fi
else
    _record_fail "full smoke matrix doc exists" "$matrix_doc not found"
fi

# ── 5. Nightly cron workflow exists and uses the report ──────────────────────
nightly="$ROOT/.github/workflows/nightly-smoke.yml"
if [[ -f "$nightly" ]]; then
    _record_pass "nightly smoke workflow exists"

    if grep -qE 'schedule:' "$nightly"; then
        _record_pass "nightly workflow has schedule trigger"
    else
        _record_fail "nightly workflow has schedule trigger" "no schedule: found"
    fi

    if grep -q 'smoke-sandcastle-report' "$nightly"; then
        _record_pass "nightly workflow runs the report aggregator"
    else
        _record_fail "nightly workflow runs the report aggregator" "no smoke-sandcastle-report reference"
    fi

    if grep -q 'upload-artifact' "$nightly"; then
        _record_pass "nightly workflow uploads report artifacts"
    else
        _record_fail "nightly workflow uploads report artifacts" "no upload-artifact step"
    fi
else
    _record_fail "nightly smoke workflow exists" "$nightly not found"
fi

# ── 6. Architecture review workflow retry guard ──────────────────────────────
architecture_installed="$ROOT/.github/workflows/agent-architecture-review.yml"
architecture_template="$ROOT/shft/templates/workflows/agent-architecture-review.yml"
if [[ -f "$architecture_installed" && -f "$architecture_template" ]]; then
    installed_architecture="$(cat "$architecture_installed")"
    template_architecture="$(cat "$architecture_template")"

    if [[ "$installed_architecture" == *"max_attempts=2"* && "$installed_architecture" == *"retrying once in 30 seconds"* ]]; then
        _record_pass "installed architecture review retries transient agent failures"
    else
        _record_fail "installed architecture review retries transient agent failures" "missing bounded retry wrapper"
    fi

    if [[ "$template_architecture" == *"max_attempts=2"* && "$template_architecture" == *"retrying once in 30 seconds"* ]]; then
        _record_pass "template architecture review retries transient agent failures"
    else
        _record_fail "template architecture review retries transient agent failures" "missing bounded retry wrapper"
    fi

    if [[ "$installed_architecture" == *"timeout-minutes: 45"* && "$template_architecture" == *"timeout-minutes: 45"* ]]; then
        _record_pass "architecture review timeout accommodates retry"
    else
        _record_fail "architecture review timeout accommodates retry" "expected timeout-minutes: 45 in installed workflow and template"
    fi
else
    _record_fail "architecture review retry guard inputs exist" "installed workflow or template missing"
fi

# ── 7. Sandcastle runner invocation drift guard ──────────────────────────────
stable_runner_pattern="pnpm --ignore-workspace exec tsx ../run.ts"
direct_binary_pattern="node_modules/.bin/tsx"

template_workflows=("$ROOT"/shft/templates/workflows/agent-*.yml)
installed_workflows=("$ROOT"/.github/workflows/agent-*.yml)

template_direct_matches="$(grep -nF "$direct_binary_pattern" "${template_workflows[@]}" 2>/dev/null || true)"
if [[ -z "$template_direct_matches" ]]; then
    _record_pass "template agent workflows avoid direct tsx binary path"
else
    _record_fail "template agent workflows avoid direct tsx binary path" "$template_direct_matches"
fi

installed_direct_matches="$(grep -nF "$direct_binary_pattern" "${installed_workflows[@]}" 2>/dev/null || true)"
if [[ -z "$installed_direct_matches" ]]; then
    _record_pass "installed agent workflows avoid direct tsx binary path"
else
    _record_fail "installed agent workflows avoid direct tsx binary path" "$installed_direct_matches"
fi

template_runner_count="$({ grep -hF "$stable_runner_pattern" "${template_workflows[@]}" 2>/dev/null || true; } | wc -l | tr -d ' ')"
if [[ "$template_runner_count" == "11" ]]; then
    _record_pass "template agent workflows use isolated pnpm runner invocation (11)"
else
    _record_fail "template agent workflows use isolated pnpm runner invocation" "found $template_runner_count, expected 11"
fi

installed_runner_count="$({ grep -hF "$stable_runner_pattern" "${installed_workflows[@]}" 2>/dev/null || true; } | wc -l | tr -d ' ')"
if [[ "$installed_runner_count" == "11" ]]; then
    _record_pass "installed agent workflows use isolated pnpm runner invocation (11)"
else
    _record_fail "installed agent workflows use isolated pnpm runner invocation" "found $installed_runner_count, expected 11"
fi

missing_template_preflight=""
for wf in "${template_workflows[@]}"; do
    if grep -qF "$stable_runner_pattern" "$wf" && ! grep -qF "id: proxy-preflight" "$wf"; then
        missing_template_preflight+="$wf"$'\n'
    fi
done
if [[ -z "$missing_template_preflight" ]]; then
    _record_pass "template model workflows include proxy preflight"
else
    _record_fail "template model workflows include proxy preflight" "$missing_template_preflight"
fi

missing_installed_preflight=""
for wf in "${installed_workflows[@]}"; do
    if grep -qF "$stable_runner_pattern" "$wf" && ! grep -qF "id: proxy-preflight" "$wf"; then
        missing_installed_preflight+="$wf"$'\n'
    fi
done
if [[ -z "$missing_installed_preflight" ]]; then
    _record_pass "installed model workflows include proxy preflight"
else
    _record_fail "installed model workflows include proxy preflight" "$missing_installed_preflight"
fi

find_ungated_dispatches() {
    local wf
    for wf in "$@"; do
        awk -v file="$wf" -v pattern="$stable_runner_pattern" '
            {
                window[NR % 12] = $0
                if (index($0, pattern) > 0) {
                    gated = 0
                    for (i = NR - 11; i <= NR; i++) {
                        if (i > 0 && window[i % 12] ~ /steps\.proxy-preflight\.outputs\.should_run == '\''true'\''/) {
                            gated = 1
                        }
                    }
                    if (!gated) {
                        print file ":" NR ": missing proxy preflight gate near run.ts dispatch"
                    }
                }
            }
        ' "$wf"
    done
}

template_ungated_dispatches="$(find_ungated_dispatches "${template_workflows[@]}")"
if [[ -z "$template_ungated_dispatches" ]]; then
    _record_pass "template run.ts dispatches are gated by proxy preflight"
else
    _record_fail "template run.ts dispatches are gated by proxy preflight" "$template_ungated_dispatches"
fi

installed_ungated_dispatches="$(find_ungated_dispatches "${installed_workflows[@]}")"
if [[ -z "$installed_ungated_dispatches" ]]; then
    _record_pass "installed run.ts dispatches are gated by proxy preflight"
else
    _record_fail "installed run.ts dispatches are gated by proxy preflight" "$installed_ungated_dispatches"
fi

# ── 7b. Composite action template drift guard ─────────────────────────────────
template_actions_dir="$ROOT/shft/templates/actions"
installed_actions_dir="$ROOT/.github/actions"

for action_name in sandcastle-setup sandcastle-teardown; do
    template_action="$template_actions_dir/$action_name/action.yml"
    installed_action="$installed_actions_dir/$action_name/action.yml"

    if [[ -f "$template_action" ]]; then
        _record_pass "template action exists: $action_name"
    else
        _record_fail "template action exists: $action_name" "$template_action missing"
        continue
    fi

    if [[ -f "$installed_action" ]]; then
        _record_pass "installed action exists: $action_name"
    else
        _record_fail "installed action exists: $action_name" "$installed_action missing"
        continue
    fi

    if diff -q "$template_action" "$installed_action" >/dev/null 2>&1; then
        _record_pass "installed action matches template: $action_name"
    else
        _record_fail "installed action matches template: $action_name" "$installed_action differs from $template_action"
    fi

    if grep -Eq "inputs\.[A-Za-z0-9]+-" "$template_action" "$installed_action"; then
        _record_fail "action avoids dot syntax for hyphenated inputs: $action_name" "found inputs.<hyphenated-key>"
    else
        _record_pass "action avoids dot syntax for hyphenated inputs: $action_name"
    fi
done

setup_action="$template_actions_dir/sandcastle-setup/action.yml"
if [[ -r "$setup_action" ]]; then
    trigger_label_required="$(awk '
        /^  trigger-label:/ { in_block=1; next }
        in_block && /^  [A-Za-z0-9_-]+:/ { in_block=0 }
        in_block && /required:[[:space:]]*true/ { print "true"; exit }
    ' "$setup_action")"
else
    trigger_label_required="missing"
fi
if [[ "${trigger_label_required:-}" == "true" ]]; then
    _record_fail "sandcastle-setup allows setup-only callers" "trigger-label remains required"
elif [[ "${trigger_label_required:-}" == "missing" ]]; then
    _record_fail "sandcastle-setup allows setup-only callers" "$setup_action missing or unreadable"
else
    _record_pass "sandcastle-setup allows setup-only callers"
fi

if grep -qF "name: Validate lifecycle inputs" "$template_actions_dir/sandcastle-setup/action.yml"; then
    _record_pass "sandcastle-setup validates lifecycle inputs"
else
    _record_fail "sandcastle-setup validates lifecycle inputs" "missing explicit validation step"
fi

if grep -Eq "default:[[:space:]]*\\$\\{\\{ github\\." "$template_actions_dir"/*/action.yml "$installed_actions_dir"/*/action.yml; then
    _record_fail "composite actions avoid expression defaults" "action inputs cannot use github.* expression defaults"
else
    _record_pass "composite actions avoid expression defaults"
fi

if grep -Eq "description:.*\\$\\{\\{" "$template_actions_dir"/*/action.yml "$installed_actions_dir"/*/action.yml; then
    _record_fail "composite action descriptions avoid expressions" "metadata descriptions are parsed before workflow contexts exist"
else
    _record_pass "composite action descriptions avoid expressions"
fi

if awk '
    /^  [A-Za-z0-9_-]+:/ {
        current=$1
        sub(/:$/, "", current)
        next
    }
    current == "repository" && /required:[[:space:]]*true/ { repository_required=1 }
    current == "checkout-ref" && /required:[[:space:]]*true/ { checkout_ref_required=1 }
    END { exit !(repository_required && checkout_ref_required) }
' "$template_actions_dir/sandcastle-setup/action.yml"; then
    _record_pass "sandcastle-setup requires explicit checkout inputs"
else
    _record_fail "sandcastle-setup requires explicit checkout inputs" "repository and checkout-ref must be explicit"
fi

if awk '
    /^  repository:/ { in_repository=1; next }
    in_repository && /^  [A-Za-z0-9_-]+:/ { in_repository=0 }
    in_repository && /required:[[:space:]]*true/ { repository_required=1 }
    END { exit !repository_required }
' "$template_actions_dir/sandcastle-teardown/action.yml"; then
    _record_pass "sandcastle-teardown requires explicit repository"
else
    _record_fail "sandcastle-teardown requires explicit repository" "repository must be explicit"
fi

if grep -qF 'gh "${{ inputs['"'"'object-type'"'"'] }}" comment' "$template_actions_dir/sandcastle-teardown/action.yml" &&
    grep -qF ')" || true' "$template_actions_dir/sandcastle-teardown/action.yml"; then
    _record_pass "sandcastle-teardown comments best-effort"
else
    _record_fail "sandcastle-teardown comments best-effort" "failure comment can fail teardown"
fi

if grep -qF "FAILURE_CONTEXT:" "$template_actions_dir/sandcastle-teardown/action.yml" &&
    grep -qF 'context="$FAILURE_CONTEXT"' "$template_actions_dir/sandcastle-teardown/action.yml" &&
    ! grep -qF 'context="${{ inputs['"'"'failure-context'"'"'] }}"' "$template_actions_dir/sandcastle-teardown/action.yml"; then
    _record_pass "sandcastle-teardown reads failure context from env"
else
    _record_fail "sandcastle-teardown reads failure context from env" "failure-context is interpolated directly into shell"
fi

# Tracer migration guard for #155: migrated workflows should use the shared
# lifecycle action contract instead of copied setup/teardown boilerplate.
migrated_lifecycle_workflows=(
    agent-plan-issue.yml
    agent-review-issue.yml
    agent-implement-issue.yml
    agent-implement-prd.yml
    agent-fix-pr-feedback.yml
    agent-merge-pr.yml
    agent-update-branch.yml
)

shared_setup_workflows=(
    agent-architecture-review.yml
    agent-check-stale-prs.yml
)

skip_checkout_workflows=(
    agent-plan-issue.yml
    agent-review-issue.yml
    agent-architecture-review.yml
    agent-check-stale-prs.yml
)

teardown_restore_workflows=(
    agent-fix-pr-feedback.yml
    agent-merge-pr.yml
    agent-update-branch.yml
)

for wf_file in "${migrated_lifecycle_workflows[@]}"; do
    wf_path="$ROOT/shft/templates/workflows/$wf_file"
    wf_label="${wf_path#$ROOT/}"
    if grep -qF "name: Checkout workflow actions" "$wf_path"; then
        _record_pass "$wf_label bootstraps local action checkout"
    else
        _record_fail "$wf_label bootstraps local action checkout" "local composite actions require a prior checkout"
    fi

    if grep -qF "uses: ./.github/actions/sandcastle-setup" "$wf_path"; then
        _record_pass "$wf_label uses sandcastle-setup action"
    else
        _record_fail "$wf_label uses sandcastle-setup action" "missing setup action"
    fi

    if grep -qF "uses: ./.github/actions/sandcastle-teardown" "$wf_path"; then
        _record_pass "$wf_label uses sandcastle-teardown action"
    else
        _record_fail "$wf_label uses sandcastle-teardown action" "missing teardown action"
    fi

    if grep -qF "Install engine dependencies" "$wf_path"; then
        _record_fail "$wf_label removes inline engine install" "still contains copied install step"
    else
        _record_pass "$wf_label removes inline engine install"
    fi

    if [ "$wf_file" = "agent-implement-issue.yml" ] || [ "$wf_file" = "agent-implement-prd.yml" ] || [ "$wf_file" = "agent-update-branch.yml" ]; then
        if grep -qF "checkout-fetch-depth: 0" "$wf_path"; then
            _record_pass "$wf_label preserves full-history checkout"
        else
            _record_fail "$wf_label preserves full-history checkout" "missing checkout-fetch-depth: 0"
        fi
    fi

    if [ "$wf_file" = "agent-implement-issue.yml" ] || [ "$wf_file" = "agent-implement-prd.yml" ]; then
        if grep -qF 'checkout-token: ${{ secrets.AGENT_PAT || secrets.GITHUB_TOKEN }}' "$wf_path"; then
            _record_pass "$wf_label preserves checkout token"
        else
            _record_fail "$wf_label preserves checkout token" "missing checkout-token"
        fi
    fi
done

for wf_file in "${shared_setup_workflows[@]}"; do
    wf_path="$ROOT/shft/templates/workflows/$wf_file"
    wf_label="${wf_path#$ROOT/}"
    if grep -qF "name: Checkout workflow actions" "$wf_path"; then
        _record_pass "$wf_label bootstraps local action checkout"
    else
        _record_fail "$wf_label bootstraps local action checkout" "local composite actions require a prior checkout"
    fi

    if grep -qF "uses: ./.github/actions/sandcastle-setup" "$wf_path"; then
        _record_pass "$wf_label uses sandcastle-setup action"
    else
        _record_fail "$wf_label uses sandcastle-setup action" "missing setup action"
    fi

    if grep -qF "Install engine dependencies" "$wf_path"; then
        _record_fail "$wf_label removes inline engine install" "still contains copied install step"
    else
        _record_pass "$wf_label removes inline engine install"
    fi
done

for wf_file in "${migrated_lifecycle_workflows[@]}"; do
    wf_path="$ROOT/.github/workflows/$wf_file"
    wf_label="${wf_path#$ROOT/}"
    if grep -qF "name: Checkout workflow actions" "$wf_path"; then
        _record_pass "$wf_label bootstraps local action checkout"
    else
        _record_fail "$wf_label bootstraps local action checkout" "local composite actions require a prior checkout"
    fi

    if grep -qF "uses: ./.github/actions/sandcastle-setup" "$wf_path"; then
        _record_pass "$wf_label uses sandcastle-setup action"
    else
        _record_fail "$wf_label uses sandcastle-setup action" "missing setup action"
    fi

    if grep -qF "uses: ./.github/actions/sandcastle-teardown" "$wf_path"; then
        _record_pass "$wf_label uses sandcastle-teardown action"
    else
        _record_fail "$wf_label uses sandcastle-teardown action" "missing teardown action"
    fi

    if grep -qF "Install engine dependencies" "$wf_path"; then
        _record_fail "$wf_label removes inline engine install" "still contains copied install step"
    else
        _record_pass "$wf_label removes inline engine install"
    fi
done

for wf_file in "${shared_setup_workflows[@]}"; do
    wf_path="$ROOT/.github/workflows/$wf_file"
    wf_label="${wf_path#$ROOT/}"
    if grep -qF "name: Checkout workflow actions" "$wf_path"; then
        _record_pass "$wf_label bootstraps local action checkout"
    else
        _record_fail "$wf_label bootstraps local action checkout" "local composite actions require a prior checkout"
    fi

    if grep -qF "uses: ./.github/actions/sandcastle-setup" "$wf_path"; then
        _record_pass "$wf_label uses sandcastle-setup action"
    else
        _record_fail "$wf_label uses sandcastle-setup action" "missing setup action"
    fi

    if grep -qF "Install engine dependencies" "$wf_path"; then
        _record_fail "$wf_label removes inline engine install" "still contains copied install step"
    else
        _record_pass "$wf_label removes inline engine install"
    fi
done

for wf_file in "${skip_checkout_workflows[@]}"; do
    wf_path="$ROOT/shft/templates/workflows/$wf_file"
    wf_label="${wf_path#$ROOT/}"
    if grep -qF "skip-checkout: true" "$wf_path"; then
        _record_pass "$wf_label skips duplicate setup checkout"
    else
        _record_fail "$wf_label skips duplicate setup checkout" "missing skip-checkout: true"
    fi
done

for wf_file in "${skip_checkout_workflows[@]}"; do
    wf_path="$ROOT/.github/workflows/$wf_file"
    wf_label="${wf_path#$ROOT/}"
    if grep -qF "skip-checkout: true" "$wf_path"; then
        _record_pass "$wf_label skips duplicate setup checkout"
    else
        _record_fail "$wf_label skips duplicate setup checkout" "missing skip-checkout: true"
    fi
done

for wf_file in "${teardown_restore_workflows[@]}"; do
    wf_path="$ROOT/shft/templates/workflows/$wf_file"
    wf_label="${wf_path#$ROOT/}"
    if grep -qF "name: Restore workflow actions" "$wf_path"; then
        _record_pass "$wf_label restores local actions before teardown"
    else
        _record_fail "$wf_label restores local actions before teardown" "missing final default-branch checkout"
    fi
done

for wf_file in "${teardown_restore_workflows[@]}"; do
    wf_path="$ROOT/.github/workflows/$wf_file"
    wf_label="${wf_path#$ROOT/}"
    if grep -qF "name: Restore workflow actions" "$wf_path"; then
        _record_pass "$wf_label restores local actions before teardown"
    else
        _record_fail "$wf_label restores local actions before teardown" "missing final default-branch checkout"
    fi
done

for wf_path in "$ROOT"/shft/templates/workflows/agent-*.yml; do
    wf_label="${wf_path#$ROOT/}"
    if grep -qF "GH_TOKEN:" "$wf_path"; then
        _record_fail "$wf_label uses GITHUB_TOKEN env naming" "still contains GH_TOKEN env key"
    else
        _record_pass "$wf_label uses GITHUB_TOKEN env naming"
    fi

    if grep -qF 'OUTPUT_DIR: ${{ runner.temp }}' "$wf_path"; then
        _record_fail "$wf_label relies on setup action for OUTPUT_DIR" "still sets OUTPUT_DIR manually"
    else
        _record_pass "$wf_label relies on setup action for OUTPUT_DIR"
    fi
done

for wf_path in "$ROOT"/.github/workflows/agent-*.yml; do
    wf_label="${wf_path#$ROOT/}"
    if grep -qF "GH_TOKEN:" "$wf_path"; then
        _record_fail "$wf_label uses GITHUB_TOKEN env naming" "still contains GH_TOKEN env key"
    else
        _record_pass "$wf_label uses GITHUB_TOKEN env naming"
    fi

    if grep -qF 'OUTPUT_DIR: ${{ runner.temp }}' "$wf_path"; then
        _record_fail "$wf_label relies on setup action for OUTPUT_DIR" "still sets OUTPUT_DIR manually"
    else
        _record_pass "$wf_label relies on setup action for OUTPUT_DIR"
    fi
done

prd_workflow="$ROOT/shft/templates/workflows/agent-implement-prd.yml"
if grep -qF "failure-context: while implementing sub-issue #" "$prd_workflow"; then
    _record_fail "agent-implement-prd omits empty failure context" "failure-context is unconditional"
else
    _record_pass "agent-implement-prd omits empty failure context"
fi

template_sandcastle_package="$ROOT/shft/templates/package.json"
installed_sandcastle_package="$ROOT/.sandcastle/package.json"
if [[ -f "$template_sandcastle_package" ]] && grep -q '"type"[[:space:]]*:[[:space:]]*"module"' "$template_sandcastle_package"; then
    _record_pass "template Sandcastle dispatcher package pins ESM"
else
    _record_fail "template Sandcastle dispatcher package pins ESM" "expected shft/templates/package.json with type=module"
fi

if [[ -f "$installed_sandcastle_package" ]] && grep -q '"type"[[:space:]]*:[[:space:]]*"module"' "$installed_sandcastle_package"; then
    _record_pass "installed Sandcastle dispatcher package pins ESM"
else
    _record_fail "installed Sandcastle dispatcher package pins ESM" "expected .sandcastle/package.json with type=module"
fi

for wf_path in "$ROOT/shft/templates/workflows/sandcastle-ci.yml" "$ROOT/.github/workflows/sandcastle-ci.yml"; do
    wf_label="${wf_path#$ROOT/}"
    package_path_count="$(grep -cF '      - ".sandcastle/package.json"' "$wf_path" || true)"
    run_path_count="$(grep -cF '      - ".sandcastle/run.ts"' "$wf_path" || true)"

    if [[ "$package_path_count" -eq 2 ]]; then
        _record_pass "$wf_label includes dispatcher package path filters"
    else
        _record_fail "$wf_label includes dispatcher package path filters" "expected path in push and pull_request filters"
    fi

    if [[ "$run_path_count" -eq 2 ]]; then
        _record_pass "$wf_label includes dispatcher run path filters"
    else
        _record_fail "$wf_label includes dispatcher run path filters" "expected path in push and pull_request filters"
    fi
done

# ── 8. Smoke test scripts exist for each smoke script ────────────────────────
# Each bin/smoke-sandcastle-*.sh should have a corresponding test file.
# Naming conventions vary (sandcastle-FOO-smoke.sh, sandcastle-FOO.sh, etc.),
# so we use a broad glob to find any test file whose name contains the key stem.
echo ""
echo "  Smoke test harness coverage:"
for smoke in "$ROOT"/bin/smoke-sandcastle-*.sh; do
    [[ -f "$smoke" ]] || continue
    smoke_base="$(basename "$smoke" .sh)"
    # Extract the key stem: smoke-sandcastle-dispatch -> dispatch
    key_stem="${smoke_base#smoke-sandcastle-}"

    # Look for any test file matching *sandcastle*KEY_STEM*
    # Also try without trailing 's' (issue-labels -> issue-label) for naming variants.
    found_test=""
    for pattern in "$key_stem" "${key_stem%s}"; do
        for candidate in "$ROOT"/test/sandcastle-*"$pattern"*.sh; do
            if [[ -f "$candidate" ]]; then
                found_test="$(basename "$candidate")"
                break 2
            fi
        done
    done

    if [[ -n "$found_test" ]]; then
        _record_pass "test exists for $smoke_base ($found_test)"
    else
        _record_fail "test exists for $smoke_base" "no test/sandcastle-*${key_stem}*.sh found"
    fi
done

# ── 9. QA baseline doc exists ────────────────────────────────────────────────
baseline_doc="$ROOT/docs/sandcastle-dogfood-baseline.md"
if [[ -f "$baseline_doc" ]]; then
    _record_pass "QA dogfood baseline document exists"
else
    _record_fail "QA dogfood baseline document exists" "expected docs/sandcastle-dogfood-baseline.md"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

printf "\n  \033[32m%d passed\033[0m  \033[31m%d failed\033[0m\n" "$PASS" "$FAIL"

if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo
    echo "Failures:"
    for failure in "${FAILURES[@]}"; do
        printf "  \033[31m✗\033[0m %s\n" "$failure"
    done
    exit 1
fi
