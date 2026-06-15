#!/usr/bin/env bash
# validate-git-hooks.sh — Verify global git hook dispatchers cannot drift.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# shellcheck source=_lib.sh
source "$ROOT/bin/_lib.sh"

_fail=0
_tmp_files=()

cleanup() {
    local file
    for file in "${_tmp_files[@]}"; do
        rm -f "$file" 2>/dev/null || true
    done
}
trap cleanup EXIT

hook_path() {
    printf '%s/git-hooks/%s\n' "$ROOT" "$1"
}

record_fail() {
    red "  ✗ $1"
    _fail=1
}

record_pass() {
    green "  ✓ $1"
}

hook_body() {
    local hook="$1"
    awk 'found || /^set -euo pipefail$/ { found=1; print }' "$(hook_path "$hook")"
}

compare_hook_body() {
    local expected="$1" actual="$2" label="$3"
    local expected_file actual_file
    expected_file="$(mktemp)"
    actual_file="$(mktemp)"
    _tmp_files+=("$expected_file" "$actual_file")

    hook_body "$expected" > "$expected_file"
    hook_body "$actual" > "$actual_file"

    if diff -u "$expected_file" "$actual_file" >/dev/null; then
        record_pass "$label matches $expected"
    else
        record_fail "$label drifted from $expected"
        diff -u "$expected_file" "$actual_file" >&2 || true
    fi
}

compare_delegation_tail() {
    local expected="$1" actual="$2" label="$3"
    local expected_file actual_file
    expected_file="$(mktemp)"
    actual_file="$(mktemp)"
    _tmp_files+=("$expected_file" "$actual_file")

    awk 'found || /^# ── 1\. Delegate to Husky/ { found=1; print }' "$(hook_path "$expected")" > "$expected_file"
    awk 'found || /^# ── 1\. Delegate to Husky/ { found=1; print }' "$(hook_path "$actual")" > "$actual_file"

    if diff -u "$expected_file" "$actual_file" >/dev/null; then
        record_pass "$label delegation tail matches $expected"
    else
        record_fail "$label delegation tail drifted from $expected"
        diff -u "$expected_file" "$actual_file" >&2 || true
    fi
}

check_hook_exists() {
    local hook="$1"
    if [[ -f "$(hook_path "$hook")" ]]; then
        record_pass "git-hooks/$hook exists"
    else
        record_fail "git-hooks/$hook missing"
    fi
}

check_hook_readable() {
    local hook="$1"
    if [[ -r "$(hook_path "$hook")" ]]; then
        record_pass "git-hooks/$hook is readable"
    else
        record_fail "git-hooks/$hook is not readable"
    fi
}

echo "Git hook drift:"

for hook in generic-hook commit-msg post-commit prepare-commit-msg pre-commit pre-push; do
    check_hook_exists "$hook"
    check_hook_readable "$hook"
done

for hook in commit-msg post-commit prepare-commit-msg; do
    compare_hook_body generic-hook "$hook" "git-hooks/$hook"
done

compare_delegation_tail generic-hook pre-push "git-hooks/pre-push"

if grep -q 'is_public_ctrlshft_remote_url' "$(hook_path pre-push)"; then
    record_pass "pre-push uses shared ctrlshft remote URL matcher"
else
    record_fail "pre-push does not use shared ctrlshft remote URL matcher"
fi

if grep -q 'Global fallback' "$(hook_path pre-commit)" && grep -q 'package.json' "$(hook_path pre-commit)"; then
    record_pass "pre-commit remains the canonical feedback-loop dispatcher"
else
    record_fail "pre-commit feedback-loop dispatcher shape changed"
fi

exit "$_fail"
