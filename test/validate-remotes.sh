#!/usr/bin/env bash
# validate-remotes.sh tests
#
# Run: bash test/validate-remotes.sh

set -euo pipefail

# Hermetic git env: git exports GIT_DIR/GIT_WORK_TREE when invoking hooks and the
# cd-hook can pollute them, which would override `git -C "$repo"` and hijack the
# temp-repo fixtures onto the real repo. Unset them (mirrors test/lifecycle.sh).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR \
      GIT_OBJECT_DIRECTORY GIT_NAMESPACE 2>/dev/null || true

if repo_root_raw="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    REPO_ROOT="$(cd "$repo_root_raw" && pwd -P)"
else
    REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
fi
VALIDATOR="$REPO_ROOT/bin/validate-remotes.sh"

TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
TMP_REPOS=()

make_repo() {
    local repo
    repo="$(mktemp -d)"
    git -C "$repo" init -b main --quiet
    git -C "$repo" config user.email test@example.com
    git -C "$repo" config user.name "Test User"
    touch "$repo/README.md"
    git -C "$repo" add README.md
    git -C "$repo" commit -m "init" --quiet
    TMP_REPOS+=("$repo")
    printf '%s\n' "$repo"
}

cleanup() {
    for repo in "${TMP_REPOS[@]}"; do
        rm -rf "$repo" 2>/dev/null || true
    done
}
trap cleanup EXIT

run_validator() {
    local repo="$1"
    set +e
    OUTPUT="$(cd "$repo" && bash "$VALIDATOR" 2>&1)"
    EXIT_CODE=$?
    set -e
}

assert_pass() {
    local name="$1"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    if [[ "$EXIT_CODE" -eq 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        printf 'PASS %s\n' "$name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf 'FAIL %s — expected pass, got %d\n%s\n' "$name" "$EXIT_CODE" "$OUTPUT"
    fi
}

assert_fail_matching() {
    local name="$1"
    local pattern="$2"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    if [[ "$EXIT_CODE" -ne 0 ]] && grep -qiE "$pattern" <<< "$OUTPUT"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        printf 'PASS %s\n' "$name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf 'FAIL %s — expected failure matching %s, got %d\n%s\n' "$name" "$pattern" "$EXIT_CODE" "$OUTPUT"
    fi
}

configure_private_remotes() {
    local repo="$1"
    git -C "$repo" remote add origin https://github.com/arndvs/dotfiles-private.git
    git -C "$repo" remote add public https://github.com/arndvs/ctrlshft.git
    git -C "$repo" remote set-url --push public DISABLED
    git -C "$repo" config remote.pushDefault origin
    git -C "$repo" config branch.main.remote origin
    git -C "$repo" config branch.main.merge refs/heads/main
}

echo "=== validate-remotes.sh tests ==="

repo="$(make_repo)"
git -C "$repo" remote add origin https://github.com/arndvs/ctrlshft.git
run_validator "$repo"
assert_pass "public checkout does not require private remotes"

repo="$(make_repo)"
configure_private_remotes "$repo"
run_validator "$repo"
assert_pass "valid private topology"

repo="$(make_repo)"
git -C "$repo" remote add origin git@github.com:arndvs/dotfiles-private.git
git -C "$repo" remote add public ssh://git@github.com/arndvs/ctrlshft.git
git -C "$repo" remote set-url --push public DISABLED
git -C "$repo" config remote.pushDefault origin
git -C "$repo" config branch.main.remote origin
git -C "$repo" config branch.main.merge refs/heads/main
run_validator "$repo"
assert_pass "ssh private topology normalizes like https"

repo="$(make_repo)"
configure_private_remotes "$repo"
git -C "$repo" config branch.main.remote public
run_validator "$repo"
assert_fail_matching "protected main cannot track public" 'main.*public|public.*main'

repo="$(make_repo)"
configure_private_remotes "$repo"
git -C "$repo" config --unset-all remote.public.pushurl
run_validator "$repo"
assert_fail_matching "missing public pushurl fails" 'no pushurl|push to the public'

repo="$(make_repo)"
configure_private_remotes "$repo"
git -C "$repo" remote set-url --push public no_push
run_validator "$repo"
assert_fail_matching "non-DISABLED public pushurl fails" 'pushurl is enabled|Fix:'

echo
printf '%d tests: %d passed' "$TESTS_TOTAL" "$TESTS_PASSED"
if [[ "$TESTS_FAILED" -gt 0 ]]; then
    printf ', %d failed' "$TESTS_FAILED"
fi
echo

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
