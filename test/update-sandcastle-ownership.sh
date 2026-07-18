#!/usr/bin/env bash
# test/update-sandcastle-ownership.sh — Verify update-sandcastle owns managed files.
# Usage: bash test/update-sandcastle-ownership.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$ROOT/working/tmp/update-sandcastle-ownership-test"

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

assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        _record_pass "$label"
    else
        _record_fail "$label" "expected output to contain '$needle': $haystack"
    fi
}

assert_file_matches() {
    local label="$1" expected="$2" actual="$3"
    if cmp -s "$expected" "$actual"; then
        _record_pass "$label"
    else
        _record_fail "$label" "$actual does not match $expected"
    fi
}

assert_missing() {
    local label="$1" path="$2"
    if [[ ! -e "$path" ]]; then
        _record_pass "$label"
    else
        _record_fail "$label" "$path still exists"
    fi
}

make_repo() {
    local repo="$1"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" config user.email "test@example.com"
    git -C "$repo" config user.name "Test User"
    mkdir -p "$repo/.github" "$repo/.sandcastle/engine"
    cp "$ROOT/.sandcastle/package.json" "$repo/.sandcastle/package.json"
    cp "$ROOT/.sandcastle/run.ts" "$repo/.sandcastle/run.ts"
    cp "$ROOT/.sandcastle/labels.json" "$repo/.sandcastle/labels.json"
    cp "$ROOT/.sandcastle/.sandcastle-version" "$repo/.sandcastle/.sandcastle-version"
    cp -R "$ROOT/.sandcastle/templates" "$repo/.sandcastle/templates"
    cp -R "$ROOT/.sandcastle/scripts" "$repo/.sandcastle/scripts"
    cp -R "$ROOT/.sandcastle/hooks" "$repo/.sandcastle/hooks"
    cp "$ROOT/.sandcastle/engine/package.json" "$repo/.sandcastle/engine/package.json"
    cp "$ROOT/.sandcastle/engine/tsconfig.json" "$repo/.sandcastle/engine/tsconfig.json"
    cp "$ROOT/.sandcastle/engine/pnpm-lock.yaml" "$repo/.sandcastle/engine/pnpm-lock.yaml"
    cp -R "$ROOT/.sandcastle/engine/lib" "$repo/.sandcastle/engine/lib"
    cp -R "$ROOT/.sandcastle/engine/schemas" "$repo/.sandcastle/engine/schemas"
    cp -R "$ROOT/.sandcastle/engine/workflows" "$repo/.sandcastle/engine/workflows"
    cp -R "$ROOT/.github/workflows" "$repo/.github/workflows"
    cp -R "$ROOT/.github/actions" "$repo/.github/actions"
    cp "$ROOT/.github/copilot-setup-steps.yml" "$repo/.github/copilot-setup-steps.yml"
    cp "$ROOT/sandcastle.config.json" "$repo/sandcastle.config.json"
}

run_update() {
    local repo="$1"
    shift
    (
        cd "$repo"
        DOTFILES="$ROOT" bash "$ROOT/bin/update-sandcastle.sh" "$@"
    )
}

echo
echo "update-sandcastle ownership tests"
echo "════════════════════════════════════════════════"

rm -rf "$TMP_ROOT"
mkdir -p "$TMP_ROOT"

dry_run_repo="$TMP_ROOT/dry-run"
make_repo "$dry_run_repo"
rm "$dry_run_repo/.sandcastle/run.ts"

set +e
dry_run_output="$(run_update "$dry_run_repo" --dry-run 2>&1)"
dry_run_status=$?
set -e

if [[ $dry_run_status -eq 0 ]]; then
    _record_pass "dry-run with drift exits successfully"
else
    _record_fail "dry-run with drift exits successfully" "exit $dry_run_status: $dry_run_output"
fi
assert_contains "dry-run detects missing dispatcher" "run.ts" "$dry_run_output"
assert_contains "dry-run reports dispatcher as not vendored" "not vendored" "$dry_run_output"

apply_repo="$TMP_ROOT/apply"
make_repo "$apply_repo"

printf 'console.log("stale dispatcher")\n' > "$apply_repo/.sandcastle/run.ts"
printf 'stale prompt\n' > "$apply_repo/.sandcastle/templates/prompts/removed-prompt.md"
printf 'stale schema\n' > "$apply_repo/.sandcastle/engine/schemas/removed-schema.ts"
printf 'stale script\n' > "$apply_repo/.sandcastle/scripts/removed-script.sh"
printf 'stale action\n' > "$apply_repo/.github/actions/sandcastle-setup/removed-action.yml"
printf 'name: stale\n' > "$apply_repo/.github/workflows/agent-removed.yml"

set +e
apply_output="$(printf 'a\n' | run_update "$apply_repo" 2>&1)"
apply_status=$?
set -e

if [[ $apply_status -eq 0 ]]; then
    _record_pass "apply with drift exits successfully"
else
    _record_fail "apply with drift exits successfully" "exit $apply_status: $apply_output"
fi

assert_file_matches "apply syncs dispatcher" "$ROOT/shft/templates/run.ts" "$apply_repo/.sandcastle/run.ts"
assert_missing "apply removes stale prompt" "$apply_repo/.sandcastle/templates/prompts/removed-prompt.md"
assert_missing "apply removes stale engine schema" "$apply_repo/.sandcastle/engine/schemas/removed-schema.ts"
assert_missing "apply removes stale helper script" "$apply_repo/.sandcastle/scripts/removed-script.sh"
assert_missing "apply removes stale action file" "$apply_repo/.github/actions/sandcastle-setup/removed-action.yml"
assert_missing "apply removes stale managed workflow" "$apply_repo/.github/workflows/agent-removed.yml"

printf "\n  \033[32m%d passed\033[0m  \033[31m%d failed\033[0m\n" "$PASS" "$FAIL"

if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo
    echo "Failures:"
    for failure in "${FAILURES[@]}"; do
        printf "  \033[31m✗\033[0m %s\n" "$failure"
    done
    exit 1
fi
