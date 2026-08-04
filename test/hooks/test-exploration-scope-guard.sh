#!/usr/bin/env bash
# test-exploration-scope-guard.sh — Tests for hooks/exploration-scope-guard.sh
#
# Run: bash test/hooks/test-exploration-scope-guard.sh

set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$(dirname "$0")/../..")"
source "test/hooks/test-helpers.sh"

HOOK="hooks/exploration-scope-guard.sh"

# Isolate state dir per test run so counters never bleed across suites/CI runs.
export DOTFILES
DOTFILES=$(mktemp -d)
TMP_REPOS+=("$DOTFILES")

echo "=== exploration-scope-guard.sh tests ==="
echo ""

echo "--- below threshold: no warning ---"

for i in $(seq 1 14); do
    run_hook "$HOOK" "$(make_pretooluse_tool_json "Read" "session-below")"
done
assert_allow "14th Read call — no permission decision override"
if [[ -z "$(parse_context)" ]]; then
    echo -e "\033[32mPASS\033[0m 14th Read call produces no additionalContext"
    TESTS_PASSED=$((TESTS_PASSED + 1)); TESTS_TOTAL=$((TESTS_TOTAL + 1))
else
    echo -e "\033[31mFAIL\033[0m 14th Read call unexpectedly warned: $(parse_context)"
    TESTS_FAILED=$((TESTS_FAILED + 1)); TESTS_TOTAL=$((TESTS_TOTAL + 1))
fi

echo ""
echo "--- 15th raw exploration call: advisory warning ---"

run_hook "$HOOK" "$(make_pretooluse_tool_json "Read" "session-below")"
assert_warn "15th Read call warns to delegate" "subagent"

echo ""
echo "--- Grep and Glob count toward the same counter ---"

run_hook "$HOOK" "$(make_pretooluse_tool_json "Grep" "session-mixed")"
run_hook "$HOOK" "$(make_pretooluse_tool_json "Glob" "session-mixed")"
for i in $(seq 1 13); do
    run_hook "$HOOK" "$(make_pretooluse_tool_json "Read" "session-mixed")"
done
assert_warn "15th mixed Read/Grep/Glob call warns" "subagent"

echo ""
echo "--- escalation past 30 calls ---"

for i in $(seq 1 29); do
    run_hook "$HOOK" "$(make_pretooluse_tool_json "Read" "session-escalate")"
done
run_hook "$HOOK" "$(make_pretooluse_tool_json "Read" "session-escalate")"
assert_warn "30th call escalates tone" "without delegating"

echo ""
echo "--- Task spawn resets the counter ---"

for i in $(seq 1 14); do
    run_hook "$HOOK" "$(make_pretooluse_tool_json "Read" "session-reset")"
done
run_hook "$HOOK" "$(make_pretooluse_tool_json "Task" "session-reset")"
run_hook "$HOOK" "$(make_pretooluse_tool_json "Read" "session-reset")"
if [[ -z "$(parse_context)" ]]; then
    echo -e "\033[32mPASS\033[0m first Read after Task reset produces no warning"
    TESTS_PASSED=$((TESTS_PASSED + 1)); TESTS_TOTAL=$((TESTS_TOTAL + 1))
else
    echo -e "\033[31mFAIL\033[0m Read after Task reset unexpectedly warned: $(parse_context)"
    TESTS_FAILED=$((TESTS_FAILED + 1)); TESTS_TOTAL=$((TESTS_TOTAL + 1))
fi

echo ""
echo "--- unrelated tool names are ignored ---"

run_hook "$HOOK" "$(make_pretooluse_tool_json "Write" "session-unrelated")"
assert_allow "Write tool call passes through untouched"
if [[ -z "$(parse_context)" ]]; then
    echo -e "\033[32mPASS\033[0m Write tool call produces no additionalContext"
    TESTS_PASSED=$((TESTS_PASSED + 1)); TESTS_TOTAL=$((TESTS_TOTAL + 1))
else
    echo -e "\033[31mFAIL\033[0m Write tool call unexpectedly warned: $(parse_context)"
    TESTS_FAILED=$((TESTS_FAILED + 1)); TESTS_TOTAL=$((TESTS_TOTAL + 1))
fi

echo ""
echo "--- Copilot Chat native tool names (read_file/grep_search/file_search/runSubagent) ---"
echo "--- (verified 2026-07-27: Copilot Chat sends its own tool names, not Claude Code's) ---"

for i in $(seq 1 14); do
    run_hook "$HOOK" "$(make_pretooluse_tool_json "read_file" "session-native")"
done
run_hook "$HOOK" "$(make_pretooluse_tool_json "grep_search" "session-native")"
assert_warn "15th native read_file/grep_search call warns" "subagent"

run_hook "$HOOK" "$(make_pretooluse_tool_json "runSubagent" "session-native")"
run_hook "$HOOK" "$(make_pretooluse_tool_json "file_search" "session-native")"
if [[ -z "$(parse_context)" ]]; then
    echo -e "\033[32mPASS\033[0m first file_search after runSubagent reset produces no warning"
    TESTS_PASSED=$((TESTS_PASSED + 1)); TESTS_TOTAL=$((TESTS_TOTAL + 1))
else
    echo -e "\033[31mFAIL\033[0m file_search after runSubagent reset unexpectedly warned: $(parse_context)"
    TESTS_FAILED=$((TESTS_FAILED + 1)); TESTS_TOTAL=$((TESTS_TOTAL + 1))
fi

report
