#!/usr/bin/env bash
# test/claude-instructions.sh — Guard conditional instructions from eager @-loading.
# Usage: bash test/claude-instructions.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$(dirname "$0")/..")"

PASS=0
FAIL=0
FAILURES=()

_ok() {
    PASS=$((PASS + 1))
    printf "  \033[32m✓\033[0m %s\n" "$1"
}

_fail() {
    FAIL=$((FAIL + 1))
    FAILURES+=("$1: $2")
    printf "  \033[31m✗\033[0m %s — %s\n" "$1" "$2"
}

assert_no_forbidden_refs() {
    local label="$1" file="$2"
    local hits grep_status
    if hits=$(grep -nE '@~/dotfiles/instructions/(nextjs|php|sanity|css|google-docs|sentry|hud)\.instructions\.md|@~/dotfiles/instructions/_local/[^[:space:]]+\.instructions\.md' "$file" 2>&1); then
        _fail "$label" "$hits"
    else
        grep_status=$?
        if [[ $grep_status -eq 1 ]]; then
            _ok "$label"
        else
            _fail "$label" "grep failed with exit $grep_status: $hits"
        fi
    fi
}

assert_contains() {
    local label="$1" needle="$2" file="$3"
    if grep -qF "$needle" "$file"; then
        _ok "$label"
    else
        _fail "$label" "missing: $needle"
    fi
}

echo
echo "Claude instruction loading guard"
echo "════════════════════════════════════════════════"

assert_no_forbidden_refs "CLAUDE.base.md has no conditional @ instruction refs" "CLAUDE.base.md"

# CLAUDE.md is bootstrap-generated and gitignored — only assert when present
if [[ -f "CLAUDE.md" ]]; then
    assert_no_forbidden_refs "CLAUDE.md has no conditional @ instruction refs" "CLAUDE.md"
    assert_contains "generated handoff remains auto-loaded" '@~/dotfiles/instructions/handoff.instructions.md' "CLAUDE.md"
else
    _ok "CLAUDE.md not present (bootstrap not run) — skipped"
fi

assert_contains "global instructions remain auto-loaded" '@~/dotfiles/global.instructions.md' "CLAUDE.base.md"
assert_contains "always-loaded handoff remains auto-loaded" '@~/dotfiles/instructions/handoff.instructions.md' "CLAUDE.base.md"

echo
echo "════════════════════════════════════════════════"
printf "  \033[32m%d passed\033[0m  \033[31m%d failed\033[0m\n" "$PASS" "$FAIL"

if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo
    echo "  Failures:"
    for f in "${FAILURES[@]}"; do
        printf "    \033[31m✗\033[0m %s\n" "$f"
    done
    echo
    exit 1
fi

echo
exit 0