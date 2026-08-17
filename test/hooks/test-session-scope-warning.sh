#!/usr/bin/env bash
# test-session-scope-warning.sh — Tests for hooks/session-scope-warning.sh
#
# Run: bash test/hooks/test-session-scope-warning.sh

set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$(dirname "$0")/../..")"
source "test/hooks/test-helpers.sh"

HOOK="hooks/session-scope-warning.sh"

# Isolate state dir per test run so counters never bleed across suites/CI runs.
export DOTFILES
DOTFILES=$(mktemp -d)
TMP_REPOS+=("$DOTFILES")

echo "=== session-scope-warning.sh tests ==="
echo ""

echo "--- below threshold: no warning ---"

for i in $(seq 1 19); do
    run_hook "$HOOK" "$(make_userpromptsubmit_json "session-below")"
done
if [[ "$HOOK_EXIT" -eq 0 && -z "$(parse_context)" ]]; then
    echo -e "\033[32mPASS\033[0m 19th prompt produces no additionalContext"
    TESTS_PASSED=$((TESTS_PASSED + 1)); TESTS_TOTAL=$((TESTS_TOTAL + 1))
else
    echo -e "\033[31mFAIL\033[0m 19th prompt unexpectedly warned or failed: $(parse_context)"
    TESTS_FAILED=$((TESTS_FAILED + 1)); TESTS_TOTAL=$((TESTS_TOTAL + 1))
fi

echo ""
echo "--- 20th turn: advisory warning ---"

run_hook "$HOOK" "$(make_userpromptsubmit_json "session-below")"
assert_warn "20th turn warns to wrap up" "wrapping up"

echo ""
echo "--- 21st turn: warning does not repeat every turn ---"

run_hook "$HOOK" "$(make_userpromptsubmit_json "session-below")"
if [[ -z "$(parse_context)" ]]; then
    echo -e "\033[32mPASS\033[0m 21st turn is silent (no per-turn spam)"
    TESTS_PASSED=$((TESTS_PASSED + 1)); TESTS_TOTAL=$((TESTS_TOTAL + 1))
else
    echo -e "\033[31mFAIL\033[0m 21st turn unexpectedly warned: $(parse_context)"
    TESTS_FAILED=$((TESTS_FAILED + 1)); TESTS_TOTAL=$((TESTS_TOTAL + 1))
fi

echo ""
echo "--- 40th turn: urgent handoff warning ---"

for i in $(seq 1 39); do
    run_hook "$HOOK" "$(make_userpromptsubmit_json "session-urgent")"
done
run_hook "$HOOK" "$(make_userpromptsubmit_json "session-urgent")"
assert_warn "40th turn urgent handoff" "handoff protocol NOW"

echo ""
echo "--- 60th turn: urgent warning repeats every 20 turns ---"

for i in $(seq 1 19); do
    run_hook "$HOOK" "$(make_userpromptsubmit_json "session-urgent")"
done
run_hook "$HOOK" "$(make_userpromptsubmit_json "session-urgent")"
assert_warn "60th turn repeats urgent handoff" "handoff protocol NOW"

echo ""
echo "--- independent sessions have independent counters ---"

run_hook "$HOOK" "$(make_userpromptsubmit_json "session-fresh")"
if [[ -z "$(parse_context)" ]]; then
    echo -e "\033[32mPASS\033[0m fresh session's 1st turn produces no warning"
    TESTS_PASSED=$((TESTS_PASSED + 1)); TESTS_TOTAL=$((TESTS_TOTAL + 1))
else
    echo -e "\033[31mFAIL\033[0m fresh session unexpectedly warned: $(parse_context)"
    TESTS_FAILED=$((TESTS_FAILED + 1)); TESTS_TOTAL=$((TESTS_TOTAL + 1))
fi

report
