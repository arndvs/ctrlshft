#!/usr/bin/env bash
# validate-git-hooks.sh tests
#
# Run: bash test/git-hooks-drift.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
VALIDATOR="$ROOT/bin/validate-git-hooks.sh"
TMP_ROOT="$ROOT/working/tmp/git-hooks-drift-test"

PASS=0
FAIL=0
FAILURES=()

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

record_pass() {
    PASS=$((PASS + 1))
    printf '  \033[32m✓\033[0m %s\n' "$1"
}

record_fail() {
    FAIL=$((FAIL + 1))
    FAILURES+=("$1 — $2")
    printf '  \033[31m✗\033[0m %s — %s\n' "$1" "$2"
}

run_case() {
    local label="$1"
    local expected="$2"
    local expected_text="$3"
    shift 3

    local output status
    set +e
    output=$("$@" 2>&1)
    status=$?
    set -e

    if [[ "$expected" == "pass" && $status -ne 0 ]]; then
        record_fail "$label" "expected pass, got $status: $output"
        return
    fi
    if [[ "$expected" == "fail" && $status -eq 0 ]]; then
        record_fail "$label" "expected failure, got success: $output"
        return
    fi
    if [[ -n "$expected_text" && "$output" != *"$expected_text"* ]]; then
        record_fail "$label" "expected output to contain '$expected_text': $output"
        return
    fi

    record_pass "$label"
}

echo
echo "Git hook drift tests"
echo "════════════════════════════════════════════════"

rm -rf "$TMP_ROOT"
mkdir -p "$TMP_ROOT/bin" "$TMP_ROOT/git-hooks"
cp "$ROOT/bin/_lib.sh" "$TMP_ROOT/bin/_lib.sh"
cp "$ROOT/bin/validate-git-hooks.sh" "$TMP_ROOT/bin/validate-git-hooks.sh"
cp "$ROOT/git-hooks/"* "$TMP_ROOT/git-hooks/"

run_case "current git hooks pass drift check" pass "pre-push uses shared ctrlshft remote URL matcher" \
    bash "$VALIDATOR"

printf '\necho drift\n' >> "$TMP_ROOT/git-hooks/commit-msg"
run_case "modified generic copy fails drift check" fail "commit-msg drifted from generic-hook" \
    bash "$TMP_ROOT/bin/validate-git-hooks.sh"

printf "\n  \033[32m%d passed\033[0m  \033[31m%d failed\033[0m\n" "$PASS" "$FAIL"

if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo
    echo "Failures:"
    for failure in "${FAILURES[@]}"; do
        printf '  \033[31m✗\033[0m %s\n' "$failure"
    done
    exit 1
fi
