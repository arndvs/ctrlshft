#!/usr/bin/env bash
# test-hooklib.sh — Tests for hooks/_hooklib.sh shared guard primitives.
#
# Run: bash test/hooks/test-hooklib.sh

set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$(dirname "$0")/../..")"
source "test/hooks/test-helpers.sh"
source "hooks/_hooklib.sh"

echo "=== _hooklib.sh tests ==="
echo ""

assert_match() {
    local test_name="$1"
    local value="$2"
    local regex="$3"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    if [[ "$value" =~ $regex ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        printf "${GREEN}PASS${RESET} %s\n" "$test_name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf "${RED}FAIL${RESET} %s — expected '%s' to match '%s'\n" "$test_name" "$value" "$regex"
    fi
}

assert_no_match() {
    local test_name="$1"
    local value="$2"
    local regex="$3"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    if [[ "$value" =~ $regex ]]; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf "${RED}FAIL${RESET} %s — expected '%s' not to match '%s'\n" "$test_name" "$value" "$regex"
    else
        TESTS_PASSED=$((TESTS_PASSED + 1))
        printf "${GREEN}PASS${RESET} %s\n" "$test_name"
    fi
}

echo "--- WRAPPER_PREFIX ---"

assert_match "WRAPPER_PREFIX matches sudo wrapper" "sudo -u root git push" "^${WRAPPER_PREFIX}git[[:space:]]+push"
assert_match "WRAPPER_PREFIX matches command wrapper" "command git commit" "^${WRAPPER_PREFIX}git[[:space:]]+commit"
assert_match "WRAPPER_PREFIX matches builtin wrapper" "builtin echo ok" "^${WRAPPER_PREFIX}echo[[:space:]]+ok"
assert_match "WRAPPER_PREFIX matches env assignment wrapper" "env FOO=bar git status" "^${WRAPPER_PREFIX}git[[:space:]]+status"
assert_match "WRAPPER_PREFIX matches env unset flag wrapper" "env -u DATABASE_URL npx prisma migrate deploy" "^${WRAPPER_PREFIX}npx[[:space:]]+prisma"
assert_match "WRAPPER_PREFIX matches env ignore-environment wrapper" "env --ignore-environment npx prisma migrate deploy" "^${WRAPPER_PREFIX}npx[[:space:]]+prisma"

echo ""
echo "--- COMMAND_BOUNDARY ---"

assert_match "COMMAND_BOUNDARY matches start of string" "git push" "${COMMAND_BOUNDARY}git[[:space:]]+push"
assert_match "COMMAND_BOUNDARY matches semicolon segment" "echo ok; git push" "${COMMAND_BOUNDARY}git[[:space:]]+push"
assert_match "COMMAND_BOUNDARY matches && segment" "echo ok && git push" "${COMMAND_BOUNDARY}git[[:space:]]+push"
assert_match "COMMAND_BOUNDARY matches control keyword segment" "if true; then git push; fi" "${COMMAND_BOUNDARY}git[[:space:]]+push"
assert_no_match "COMMAND_BOUNDARY does not match quoted mention" "echo 'git push'" "${COMMAND_BOUNDARY}git[[:space:]]+push"
assert_no_match "COMMAND_BOUNDARY excludes backtick by default" 'echo `git push`' "${COMMAND_BOUNDARY}git[[:space:]]+push"
assert_match "COMMAND_BOUNDARY_WITH_BACKTICK includes backtick" 'echo `git push`' "${COMMAND_BOUNDARY_WITH_BACKTICK}git[[:space:]]+push"

echo ""
echo "--- _deny ---"

TESTS_TOTAL=$((TESTS_TOTAL + 1))
deny_stderr=$(mktemp)
deny_exit=0
( _deny "blocked for test" ) 2>"$deny_stderr" || deny_exit=$?
deny_json=$(cat "$deny_stderr")
rm -f "$deny_stderr"

deny_decision=$(printf '%s' "$deny_json" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null || true)
deny_reason=$(printf '%s' "$deny_json" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null || true)

if [[ "$deny_exit" -eq 2 && "$deny_decision" == "deny" && "$deny_reason" == "blocked for test" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}PASS${RESET} _deny exits 2 with standard JSON payload\n"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}FAIL${RESET} _deny exits 2 with standard JSON payload — exit=%s json=%s\n" "$deny_exit" "$deny_json"
fi

report
