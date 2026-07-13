#!/usr/bin/env bash
# test/main-pr-source-guard.sh — Verify main only accepts promotion PRs from dev.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$ROOT/bin/validate-main-pr-source.sh"
WORKFLOW="$ROOT/.github/workflows/main-pr-source-guard.yml"

PASS=0
FAIL=0
FAILURES=()

record_pass() {
    PASS=$((PASS + 1))
    printf "  \033[32m✓\033[0m %s\n" "$1"
}

record_fail() {
    FAIL=$((FAIL + 1))
    FAILURES+=("$1 — $2")
    printf "  \033[31m✗\033[0m %s — %s\n" "$1" "$2"
}

run_case() {
    local label="$1"
    local expected="$2"
    local base_ref="$3"
    local head_ref="$4"
    local status

    set +e
    GITHUB_BASE_REF="$base_ref" GITHUB_HEAD_REF="$head_ref" bash "$GUARD" >/dev/null 2>&1
    status=$?
    set -e

    if [[ "$expected" == "pass" && "$status" -eq 0 ]]; then
        record_pass "$label"
    elif [[ "$expected" == "fail" && "$status" -ne 0 ]]; then
        record_pass "$label"
    else
        record_fail "$label" "expected $expected for $head_ref -> $base_ref, got exit $status"
    fi
}

echo
echo "Main PR source guard tests"
echo "════════════════════════════════════════════════"

if [[ -x "$GUARD" ]]; then
    record_pass "guard script exists and is executable"
else
    record_fail "guard script exists and is executable" "$GUARD missing or not executable"
fi

if [[ -f "$WORKFLOW" ]] &&
    grep -qE '^[[:space:]]*pull_request:' "$WORKFLOW" &&
    grep -qF 'main' "$WORKFLOW" &&
    grep -qF 'bin/validate-main-pr-source.sh' "$WORKFLOW"; then
    record_pass "main PR source guard workflow is wired"
else
    record_fail "main PR source guard workflow is wired" "$WORKFLOW missing or incomplete"
fi

if [[ -f "$WORKFLOW" ]] &&
    grep -qF 'ref: ${{ github.event.pull_request.base.sha }}' "$WORKFLOW"; then
    record_pass "main PR source guard checks out trusted base commit"
else
    record_fail "main PR source guard checks out trusted base commit" "workflow must not run the guard from PR-modified code"
fi

if [[ -x "$GUARD" ]]; then
    run_case "dev may target main" pass main dev
    run_case "feature branch may not target main" fail main ai/fix/example
    run_case "feature branch may target dev" pass dev ai/fix/example
    run_case "dev may target master if present" pass master dev
    run_case "feature branch may not target master" fail master ai/fix/example
fi

printf "\n  \033[32m%d passed\033[0m  \033[31m%d failed\033[0m\n" "$PASS" "$FAIL"

if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo
    echo "Failures:"
    for failure in "${FAILURES[@]}"; do
        printf "  \033[31m✗\033[0m %s\n" "$failure"
    done
    exit 1
fi
