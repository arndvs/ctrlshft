#!/usr/bin/env bash
# test-validate-symlinks.sh — Tests for bin/validate-symlinks.sh
#
# Verifies consumer integrity validation, including Copilot instruction parity.
# Uses a fake $HOME to avoid touching real consumer paths.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VALIDATE_SCRIPT="$REPO_DIR/bin/validate-symlinks.sh"

# Colors
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'; RED='\033[0;31m'; RESET='\033[0m'
else
    GREEN=''; RED=''; RESET=''
fi

TESTS_PASSED=0
TESTS_FAILED=0

pass() { TESTS_PASSED=$((TESTS_PASSED + 1)); printf "${GREEN}PASS${RESET} %s\n" "$1"; }
fail() { TESTS_FAILED=$((TESTS_FAILED + 1)); printf "${RED}FAIL${RESET} %s\n" "$1"; }

# --- Setup fake HOME ---
setup_fake_home() {
    local tmp
    tmp=$(mktemp -d)
    export HOME="$tmp"
    export FAKE_HOME="$tmp"

    # Create fake dotfiles source
    mkdir -p "$tmp/dotfiles/skills" "$tmp/dotfiles/agents" "$tmp/dotfiles/rules" "$tmp/dotfiles/bin"
    echo "# Generated CLAUDE.md" > "$tmp/dotfiles/CLAUDE.md"
    touch "$tmp/dotfiles/bin/ctrl"
    chmod +x "$tmp/dotfiles/bin/ctrl"
    mkdir -p "$tmp/dotfiles/shft"
    touch "$tmp/dotfiles/shft/shft"
    chmod +x "$tmp/dotfiles/shft/shft"

    # Create consumer dirs
    mkdir -p "$tmp/.claude" "$tmp/.copilot" "$tmp/.agents" "$tmp/.local/bin"

    # Create valid symlinks
    ln -sf "$tmp/dotfiles/CLAUDE.md" "$tmp/.claude/CLAUDE.md"
    ln -sf "$tmp/dotfiles/skills" "$tmp/.claude/skills"
    ln -sf "$tmp/dotfiles/agents" "$tmp/.claude/agents"
    ln -sf "$tmp/dotfiles/rules" "$tmp/.claude/rules"
    ln -sf "$tmp/dotfiles/skills" "$tmp/.copilot/skills"
    ln -sf "$tmp/dotfiles/CLAUDE.md" "$tmp/.copilot/copilot-instructions.md"
    ln -sf "$tmp/dotfiles/skills" "$tmp/.agents/skills"
    ln -sf "$tmp/dotfiles/bin/ctrl" "$tmp/.local/bin/ctrl"
    ln -sf "$tmp/dotfiles/shft/shft" "$tmp/.local/bin/shft"
}

teardown_fake_home() {
    rm -rf "$FAKE_HOME" 2>/dev/null || true
}

trap teardown_fake_home EXIT

# --- Tests ---

test_all_symlinks_valid() {
    setup_fake_home
    local output exit_code=0
    output=$(bash "$VALIDATE_SCRIPT" 2>&1) || exit_code=$?
    teardown_fake_home
    if [[ $exit_code -eq 0 ]]; then
        pass "all symlinks valid — exits 0"
    else
        fail "all symlinks valid — expected exit 0, got $exit_code"
        echo "    output: $output"
    fi
}

test_copilot_instructions_missing() {
    setup_fake_home
    rm -f "$HOME/.copilot/copilot-instructions.md"
    local output exit_code=0
    output=$(bash "$VALIDATE_SCRIPT" 2>&1) || exit_code=$?
    teardown_fake_home
    if [[ $exit_code -ne 0 ]]; then
        pass "copilot-instructions.md missing — fails validation"
    else
        fail "copilot-instructions.md missing — expected failure, got exit 0"
    fi
}

test_copilot_instructions_drifted() {
    setup_fake_home
    # Replace symlink with a file containing different content
    rm -f "$HOME/.copilot/copilot-instructions.md"
    echo "# DRIFTED CONTENT" > "$HOME/.copilot/copilot-instructions.md"
    local output exit_code=0
    output=$(bash "$VALIDATE_SCRIPT" 2>&1) || exit_code=$?
    teardown_fake_home
    if [[ $exit_code -ne 0 ]]; then
        pass "copilot-instructions.md drifted — fails validation"
    else
        fail "copilot-instructions.md drifted — expected failure, got exit 0"
    fi
}

test_copilot_instructions_wrong_symlink_target() {
    setup_fake_home
    rm -f "$HOME/.copilot/copilot-instructions.md"
    ln -sf "/some/wrong/path" "$HOME/.copilot/copilot-instructions.md"
    local output exit_code=0
    output=$(bash "$VALIDATE_SCRIPT" 2>&1) || exit_code=$?
    teardown_fake_home
    if [[ $exit_code -ne 0 ]]; then
        pass "copilot-instructions.md wrong target — fails validation"
    else
        fail "copilot-instructions.md wrong target — expected failure, got exit 0"
    fi
}

test_ci_mode_skips_consumer_checks() {
    setup_fake_home
    rm -f "$HOME/.copilot/copilot-instructions.md"
    local output exit_code=0
    output=$(bash "$VALIDATE_SCRIPT" --ci 2>&1) || exit_code=$?
    teardown_fake_home
    if [[ $exit_code -eq 0 ]]; then
        pass "--ci mode skips consumer path checks"
    else
        fail "--ci mode — expected exit 0 (skipped), got $exit_code"
    fi
}

# --- Run tests ---
echo "=== validate-symlinks.sh tests ==="
test_all_symlinks_valid
test_copilot_instructions_missing
test_copilot_instructions_drifted
test_copilot_instructions_wrong_symlink_target
test_ci_mode_skips_consumer_checks

# --- Report ---
echo ""
echo "---"
TOTAL=$((TESTS_PASSED + TESTS_FAILED))
printf "%d tests: ${GREEN}%d passed${RESET}" "$TOTAL" "$TESTS_PASSED"
if [[ $TESTS_FAILED -gt 0 ]]; then
    printf ", ${RED}%d failed${RESET}" "$TESTS_FAILED"
fi
echo ""

[[ $TESTS_FAILED -eq 0 ]] || exit 1
