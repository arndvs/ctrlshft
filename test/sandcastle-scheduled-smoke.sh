#!/usr/bin/env bash
# test/sandcastle-scheduled-smoke.sh — Verify Sandcastle scheduled-workflow smoke harness behavior.
# Usage: bash test/sandcastle-scheduled-smoke.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/bin/smoke-sandcastle-scheduled.sh"
TMP_ROOT="$ROOT/working/tmp/sandcastle-scheduled-smoke-test"

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

    # Create schedule-backed workflows (both schedule: and workflow_dispatch:)
    cat > "$repo/.github/workflows/agent-architecture-review.yml" <<'YAML'
name: "Agent: Architecture Review"
on:
  schedule:
    - cron: "0 6 * * *"
  workflow_dispatch:
jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
YAML
    cat > "$repo/.github/workflows/agent-check-stale-prs.yml" <<'YAML'
name: "Agent: Check Stale PRs"
on:
  schedule:
    - cron: "0 7 * * *"
  workflow_dispatch:
jobs:
  check-stale:
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
YAML

    # The dispatch harness must also be available
    mkdir -p "$repo/bin"
    cat > "$repo/sandcastle.config.json" <<'JSON'
{
  "baseBranch": "dev"
}
JSON
}

echo
echo "Sandcastle scheduled-workflow smoke tests"
echo "════════════════════════════════════════════════"

rm -rf "$TMP_ROOT"
mkdir -p "$TMP_ROOT"

repo="$TMP_ROOT/repo"
make_repo "$repo"

# ── List mode discovers schedule-backed workflows ─────────────────────────────
run_case "list discovers schedule-backed workflows" pass "agent-architecture-review.yml" \
    bash -c "cd '$repo' && DOTFILES='$ROOT' '$SCRIPT' --list"

run_case "list includes agent-check-stale-prs.yml" pass "agent-check-stale-prs.yml" \
    bash -c "cd '$repo' && DOTFILES='$ROOT' '$SCRIPT' --list"

# ── Dry run previews dispatches ───────────────────────────────────────────────
run_case "dry run previews dispatch plan" pass "Would run (schedule-equivalent)" \
    bash -c "cd '$repo' && DOTFILES='$ROOT' '$SCRIPT' --dry-run --repo owner/repo"

# ── Dry run for single workflow ───────────────────────────────────────────────
run_case "dry run single workflow" pass "agent-check-stale-prs.yml" \
    bash -c "cd '$repo' && DOTFILES='$ROOT' '$SCRIPT' --dry-run --workflow agent-check-stale-prs.yml --repo owner/repo"

# ── Live run requires --allow-side-effects ────────────────────────────────────
run_case "live run requires side-effect opt-in" fail "Pass --allow-side-effects" \
    bash -c "cd '$repo' && DOTFILES='$ROOT' '$SCRIPT' --repo owner/repo"

# ── Unknown workflow rejected ─────────────────────────────────────────────────
run_case "unknown workflow rejected" fail "Not a discovered schedule-backed workflow" \
    bash -c "cd '$repo' && DOTFILES='$ROOT' '$SCRIPT' --dry-run --workflow not-a-workflow.yml --repo owner/repo"

printf "\n  \033[32m%d passed\033[0m  \033[31m%d failed\033[0m\n" "$PASS" "$FAIL"

if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo
    echo "Failures:"
    for failure in "${FAILURES[@]}"; do
        printf "  \033[31m✗\033[0m %s\n" "$failure"
    done
    exit 1
fi
