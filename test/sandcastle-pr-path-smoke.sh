#!/usr/bin/env bash
# test/sandcastle-pr-path-smoke.sh — Verify Sandcastle PR-path smoke harness behavior.
# Usage: bash test/sandcastle-pr-path-smoke.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/bin/smoke-sandcastle-pr-path.sh"
TMP_ROOT="$ROOT/working/tmp/sandcastle-pr-path-smoke-test"

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

make_repo() {
    local repo="$1"
    mkdir -p "$repo/.github/workflows"
    git -C "$repo" init -q
    git -C "$repo" config user.email "test@example.com"
    git -C "$repo" config user.name "Test User"
    for workflow in agent-update-branch.yml agent-fix-pr-feedback.yml agent-merge-pr.yml; do
        cat > "$repo/.github/workflows/$workflow" <<'YAML'
name: Smoke Fixture
on:
  pull_request_target:
    types: [labeled]
jobs:
  smoke:
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
YAML
    done
    cat > "$repo/sandcastle.config.json" <<'JSON'
{
  "baseBranch": "dev"
}
JSON
}

echo
echo "Sandcastle PR-path smoke tests"
echo "════════════════════════════════════════════════"

rm -rf "$TMP_ROOT"
mkdir -p "$TMP_ROOT"

repo="$TMP_ROOT/repo"
make_repo "$repo"

# ── Dry-run test ──────────────────────────────────────────────────────────────
run_case "dry run previews PR-path chain" pass "Would create branch" \
    bash -c "cd '$repo' && DOTFILES='$ROOT' '$SCRIPT' --dry-run --repo owner/repo"

# ── Dry run shows merge info when --confirm-merge ─────────────────────────────
run_case "dry run with --confirm-merge shows merge path" pass "agent:merge" \
    bash -c "cd '$repo' && DOTFILES='$ROOT' '$SCRIPT' --dry-run --confirm-merge --repo owner/repo"

# ── Live run requires --allow-side-effects ────────────────────────────────────
run_case "live run requires side-effect opt-in" fail "Pass --allow-side-effects" \
    bash -c "cd '$repo' && DOTFILES='$ROOT' '$SCRIPT' --repo owner/repo"

# ── Missing workflow fails ────────────────────────────────────────────────────
missing_wf_repo="$TMP_ROOT/missing-wf-repo"
make_repo "$missing_wf_repo"
rm -f "$missing_wf_repo/.github/workflows/agent-merge-pr.yml"
run_case "missing workflow file is detected" fail "Workflow not found" \
    bash -c "cd '$missing_wf_repo' && DOTFILES='$ROOT' '$SCRIPT' --dry-run --repo owner/repo"

printf "\n  \033[32m%d passed\033[0m  \033[31m%d failed\033[0m\n" "$PASS" "$FAIL"

if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo
    echo "Failures:"
    for failure in "${FAILURES[@]}"; do
        printf "  \033[31m✗\033[0m %s\n" "$failure"
    done
    exit 1
fi
