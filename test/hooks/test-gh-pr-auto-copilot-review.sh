#!/usr/bin/env bash
# test-gh-pr-auto-copilot-review.sh — Tests for hooks/gh-pr-auto-copilot-review.sh
#
# Run: bash test/hooks/test-gh-pr-auto-copilot-review.sh

set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$(dirname "$0")/../..")"
source "test/hooks/test-helpers.sh"

HOOK="hooks/gh-pr-auto-copilot-review.sh"
GH_CALLS=""
GH_SHIM_DIR=""
OLD_PATH="$PATH"

make_pr_create_json() {
    local command="$1"
    jq -cn --arg cmd "$command" --arg cwd "$REPO" '{
        "tool_name": "Bash",
        "tool_input": {"command": $cmd},
        "tool_result": {
            "exit_code": 0,
            "output": "https://github.com/org/repo/pull/123"
        },
        "cwd": $cwd
    }'
}

setup_gh_shim() {
    local has_request="${1:-false}"
    GH_SHIM_DIR=$(mktemp -d)
    TMP_REPOS+=("$GH_SHIM_DIR")
    GH_CALLS="$GH_SHIM_DIR/calls.log"
    export GH_CALLS
    export GH_HAS_REQUEST="$has_request"
    cat > "$GH_SHIM_DIR/gh" <<'SHIMEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_CALLS"
case "$1" in
  repo)
    echo "org/repo"
    ;;
  api)
    echo "${GH_HAS_REQUEST:-false}"
    ;;
  pr)
    if [[ "${2:-}" == "edit" ]]; then
      exit 0
    fi
    if [[ "${2:-}" == "view" ]]; then
      echo "123"
      exit 0
    fi
    ;;
esac
exit 0
SHIMEOF
    chmod +x "$GH_SHIM_DIR/gh"
    export PATH="$GH_SHIM_DIR:$OLD_PATH"
}

assert_no_gh_calls() {
    local test_name="$1"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    if [[ -s "$GH_CALLS" ]]; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf "${RED}FAIL${RESET} %s — expected no gh calls, got: %s\n" "$test_name" "$(tr '\n' ';' < "$GH_CALLS")"
        return
    fi
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}PASS${RESET} %s\n" "$test_name"
}

assert_no_pr_edit() {
    local test_name="$1"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    if grep -q '^pr edit' "$GH_CALLS" 2>/dev/null; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf "${RED}FAIL${RESET} %s — expected no gh pr edit call\n" "$test_name"
        return
    fi
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}PASS${RESET} %s\n" "$test_name"
}

assert_pr_edit_called() {
    local test_name="$1"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    if ! grep -q '^pr edit 123 -R org/repo --add-reviewer copilot-pull-request-reviewer' "$GH_CALLS" 2>/dev/null; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf "${RED}FAIL${RESET} %s — expected gh pr edit reviewer call, got: %s\n" "$test_name" "$(tr '\n' ';' < "$GH_CALLS")"
        return
    fi
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}PASS${RESET} %s\n" "$test_name"
}

echo "=== gh-pr-auto-copilot-review.sh tests ==="
echo ""

REPO=$(make_tmp_repo)

setup_gh_shim false
run_hook "$HOOK" "$(make_pr_create_json 'gh pr create --add-reviewer copilot-pull-request-reviewer')"
assert_allow "skip: command already requested Copilot reviewer"
assert_no_gh_calls "skip reviewer flag before any gh API calls"

setup_gh_shim true
run_hook "$HOOK" "$(make_pr_create_json 'gh pr create --title test')"
assert_allow "skip: Copilot already requested"
assert_no_pr_edit "skip existing Copilot request without duplicate edit"

setup_gh_shim false
run_hook "$HOOK" "$(make_pr_create_json 'gh pr create --title test')"
assert_warn "request: Copilot reviewer added" "Requested Copilot review"
assert_pr_edit_called "request reviewer via gh pr edit"

report
