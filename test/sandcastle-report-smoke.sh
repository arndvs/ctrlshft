#!/usr/bin/env bash
# test/sandcastle-report-smoke.sh — Verify Sandcastle smoke-report aggregator behavior.
# Usage: bash test/sandcastle-report-smoke.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/bin/smoke-sandcastle-report.sh"
TMP_ROOT="$ROOT/working/tmp/sandcastle-report-smoke-test"

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

run_case() {
    local label="$1"
    local expected_status="$2"
    local expected_text="$3"
    shift 3

    local output status
    set +e
    output=$("$@" 2>&1)
    status=$?
    set -e

    if [[ "$expected_status" == "pass" && $status -ne 0 ]]; then
        _record_fail "$label" "expected success, got exit $status: $output"
        return
    fi
    if [[ "$expected_status" == "fail" && $status -eq 0 ]]; then
        _record_fail "$label" "expected failure, got success: $output"
        return
    fi
    if [[ -n "$expected_text" && "$output" != *"$expected_text"* ]]; then
        _record_fail "$label" "expected output to contain '$expected_text': $output"
        return
    fi

    _record_pass "$label"
}

install_fake_gh() {
    local bin_dir="$1"
    mkdir -p "$bin_dir"
    cat > "$bin_dir/gh" <<'FAKEGH'
#!/usr/bin/env bash
set -euo pipefail

# repo view — return canonical repo slug
if [[ "$1" == "repo" && "${2:-}" == "view" ]]; then
    echo 'owner/repo'
    exit 0
fi

# run list — return canned workflow run data
if [[ "$1" == "run" && "${2:-}" == "list" ]]; then
    # Parse out --workflow value
    workflow=""
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "--workflow" ]]; then
            workflow="$2"
            shift 2
            continue
        fi
        shift
    done

    case "$workflow" in
        "Agent: Architecture Review"|"Agent: Check Stale PRs"|"Bridge Tests"|"Integrity"|"Labels: Sync"|"Sandcastle CI"|"Proxy canary")
            cat <<JSON
[{"databaseId":100,"url":"https://github.com/owner/repo/actions/runs/100","status":"completed","conclusion":"success","createdAt":"2026-06-10T00:00:00Z","displayTitle":"$workflow","event":"push"}]
JSON
            ;;
        "PR: request Copilot review")
            cat <<JSON
[{"databaseId":200,"url":"https://github.com/owner/repo/actions/runs/200","status":"completed","conclusion":"success","createdAt":"2026-06-09T00:00:00Z","displayTitle":"$workflow","event":"pull_request"}]
JSON
            ;;
        "Agent: Promote Queued")
            cat <<JSON
[{"databaseId":300,"url":"https://github.com/owner/repo/actions/runs/300","status":"completed","conclusion":"failure","createdAt":"2026-06-08T00:00:00Z","displayTitle":"$workflow","event":"issues"},{"databaseId":301,"url":"https://github.com/owner/repo/actions/runs/301","status":"completed","conclusion":"success","createdAt":"2026-06-07T00:00:00Z","displayTitle":"$workflow","event":"issues"}]
JSON
            ;;
        "Agent: Fix PR Feedback"|"Agent: Merge PR"|"Agent: Update Branch")
            # PR-path workflows — zero runs
            echo '[]'
            ;;
        *)
            # Default: one successful run
            cat <<JSON
[{"databaseId":400,"url":"https://github.com/owner/repo/actions/runs/400","status":"completed","conclusion":"success","createdAt":"2026-06-10T00:00:00Z","displayTitle":"$workflow","event":"issues"}]
JSON
            ;;
    esac
    exit 0
fi

echo "unexpected gh args: $*" >&2
exit 99
FAKEGH
    chmod +x "$bin_dir/gh"
}

echo
echo "Sandcastle report aggregator tests"
echo "════════════════════════════════════════════════"

rm -rf "$TMP_ROOT"
mkdir -p "$TMP_ROOT"

fake_bin="$TMP_ROOT/fake-bin"
install_fake_gh "$fake_bin"

# ── JSON output ───────────────────────────────────────────────────────────────

json_output="$TMP_ROOT/json-out.json"
set +e
PATH="$fake_bin:$PATH" DOTFILES="$ROOT" \
    bash "$SCRIPT" --repo owner/repo --limit 2 --json > "$json_output" 2>&1
json_status=$?
set -e

if [[ $json_status -ne 0 ]]; then
    _record_fail "JSON output exits successfully" "exit $json_status: $(cat "$json_output")"
else
    _record_pass "JSON output exits successfully"
fi

# Validate JSON is parseable
if python3 -c "import json, sys; json.load(open(sys.argv[1]))" "$json_output" 2>/dev/null; then
    _record_pass "JSON output is valid JSON"
else
    _record_fail "JSON output is valid JSON" "could not parse: $(head -5 "$json_output")"
fi

# Check report structure
if python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    report = json.load(f)
required_keys = {'repo', 'generated_at', 'summary', 'smoke_scripts', 'workflows'}
missing = required_keys - set(report.keys())
if missing:
    print(f'missing keys: {missing}', file=sys.stderr)
    sys.exit(1)
" "$json_output" 2>/dev/null; then
    _record_pass "JSON report has required top-level keys"
else
    _record_fail "JSON report has required top-level keys" "missing keys"
fi

# Check summary fields
if python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    s = json.load(f)['summary']
required = {'total_workflows', 'covered_workflows', 'coverage_pct', 'total_runs_inspected', 'pass', 'fail', 'skip'}
missing = required - set(s.keys())
if missing:
    print(f'missing summary keys: {missing}', file=sys.stderr)
    sys.exit(1)
" "$json_output" 2>/dev/null; then
    _record_pass "JSON summary has required metric keys"
else
    _record_fail "JSON summary has required metric keys" "missing summary keys"
fi

# Check total_workflows equals 16
if python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    s = json.load(f)['summary']
if s['total_workflows'] != 16:
    print(f'total_workflows={s[\"total_workflows\"]}', file=sys.stderr)
    sys.exit(1)
" "$json_output" 2>/dev/null; then
    _record_pass "report tracks all 16 Sandcastle workflows"
else
    _record_fail "report tracks all 16 Sandcastle workflows" "unexpected total_workflows count"
fi

# Check covered_workflows > 0 (at least some have run data)
if python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    s = json.load(f)['summary']
if s['covered_workflows'] <= 0:
    print(f'covered_workflows={s[\"covered_workflows\"]}', file=sys.stderr)
    sys.exit(1)
" "$json_output" 2>/dev/null; then
    _record_pass "some workflows have run data (covered > 0)"
else
    _record_fail "some workflows have run data (covered > 0)" "covered_workflows was 0"
fi

# Check that per-workflow entries include expected fields
if python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    workflows = json.load(f)['workflows']
required = {'name', 'runs', 'latest_conclusion', 'latest_url', 'latest_date', 'pass', 'fail', 'skip'}
for w in workflows:
    missing = required - set(w.keys())
    if missing:
        print(f'{w.get(\"name\",\"?\")} missing: {missing}', file=sys.stderr)
        sys.exit(1)
" "$json_output" 2>/dev/null; then
    _record_pass "per-workflow entries have required fields"
else
    _record_fail "per-workflow entries have required fields" "missing per-workflow fields"
fi

# Check workflows with zero runs are reported correctly
if python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    workflows = json.load(f)['workflows']
zero_run = [w for w in workflows if w['runs'] == 0]
if len(zero_run) == 0:
    print('expected at least one zero-run workflow', file=sys.stderr)
    sys.exit(1)
for w in zero_run:
    if w['latest_conclusion'] is not None:
        print(f'{w[\"name\"]} has runs=0 but latest_conclusion={w[\"latest_conclusion\"]}', file=sys.stderr)
        sys.exit(1)
" "$json_output" 2>/dev/null; then
    _record_pass "zero-run workflows report null conclusion"
else
    _record_fail "zero-run workflows report null conclusion" "unexpected state for zero-run workflows"
fi

# Check failure detection
if python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    s = json.load(f)['summary']
if s['fail'] <= 0:
    print('expected at least one failure from Promote Queued stub', file=sys.stderr)
    sys.exit(1)
" "$json_output" 2>/dev/null; then
    _record_pass "report detects workflow failures"
else
    _record_fail "report detects workflow failures" "expected fail > 0"
fi

# Check smoke_scripts list
if python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    scripts = json.load(f)['smoke_scripts']
if len(scripts) < 5:
    print(f'expected >= 5 smoke scripts, got {len(scripts)}', file=sys.stderr)
    sys.exit(1)
" "$json_output" 2>/dev/null; then
    _record_pass "report lists smoke scripts (>= 5)"
else
    _record_fail "report lists smoke scripts (>= 5)" "expected >= 5 smoke scripts"
fi

# ── Markdown output ──────────────────────────────────────────────────────────

md_output="$TMP_ROOT/md-out.md"
set +e
PATH="$fake_bin:$PATH" DOTFILES="$ROOT" \
    bash "$SCRIPT" --repo owner/repo --limit 2 --md > "$md_output" 2>&1
md_status=$?
set -e

if [[ $md_status -ne 0 ]]; then
    _record_fail "markdown output exits successfully" "exit $md_status: $(cat "$md_output")"
else
    _record_pass "markdown output exits successfully"
fi

if grep -q "# Sandcastle Smoke Report" "$md_output"; then
    _record_pass "markdown contains report title"
else
    _record_fail "markdown contains report title" "missing '# Sandcastle Smoke Report'"
fi

if grep -q "Per-Workflow Results" "$md_output"; then
    _record_pass "markdown contains per-workflow table"
else
    _record_fail "markdown contains per-workflow table" "missing 'Per-Workflow Results'"
fi

if grep -q "Smoke Scripts" "$md_output"; then
    _record_pass "markdown contains smoke scripts section"
else
    _record_fail "markdown contains smoke scripts section" "missing 'Smoke Scripts'"
fi

if grep -q "Coverage" "$md_output"; then
    _record_pass "markdown contains coverage metric"
else
    _record_fail "markdown contains coverage metric" "missing 'Coverage'"
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
