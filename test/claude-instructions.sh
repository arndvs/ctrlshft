#!/usr/bin/env bash
# test/claude-instructions.sh — Guard conditional instructions from eager @-loading.
#   Workspace-conditional instructions (nextjs, php, sanity, …) must never be
#   eager @-refs. Local instructions MAY be intentionally auto-loaded (e.g.
#   always-on safety rules), so a _local/ @-ref is only a violation when its
#   target file is marked `auto-load: false` — i.e. a task-triggered instruction
#   that leaked into eager loading. This mirrors bootstrap.sh's routing.
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
    local violations=()
    local tracked_hits="" local_hits="" line fname target

    # Workspace-conditional instructions are always forbidden as eager @-refs.
    local grep_status
    tracked_hits=$(grep -noE '@~/dotfiles/instructions/(nextjs|php|sanity|css|google-docs|sentry|hud)\.instructions\.md' "$file" 2>&1) && grep_status=0 || grep_status=$?
    if [[ $grep_status -eq 0 ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && violations+=("$line")
        done <<< "$tracked_hits"
    elif [[ $grep_status -ne 1 ]]; then
        _fail "$label" "grep failed with exit $grep_status: $tracked_hits"
        return
    fi

    # Local instructions may be intentionally auto-loaded. Only flag a _local/
    # @-ref whose target is marked `auto-load: false` (a task-triggered file that
    # leaked into eager loading); intentional auto-loads are allowed.
    local_hits=$(grep -noE '@~/dotfiles/instructions/_local/[^[:space:]]+\.instructions\.md' "$file" 2>&1) && grep_status=0 || grep_status=$?
    if [[ $grep_status -eq 0 ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            fname="${line##*/}"
            target="instructions/_local/$fname"
            if [[ -f "$target" ]] && head -20 "$target" | grep -qE '^auto-load:[[:space:]]*false'; then
                violations+=("$line (auto-load: false but eager-loaded)")
            fi
        done <<< "$local_hits"
    elif [[ $grep_status -ne 1 ]]; then
        _fail "$label" "grep failed with exit $grep_status: $local_hits"
        return
    fi

    if [[ ${#violations[@]} -gt 0 ]]; then
        _fail "$label" "$(printf '%s; ' "${violations[@]}")"
    else
        _ok "$label"
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