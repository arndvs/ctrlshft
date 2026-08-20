#!/usr/bin/env bash
# test/update-sandcastle-ownership.sh — Verify update-sandcastle reports hub-model deprecation.
#
# The engine is no longer vendored (hub model). update-sandcastle.sh is a
# deprecated stub that must:
#   - Print the deprecation notice naming arndvs/sandcastle-hub as the source
#   - Print the hub release path (hub/release.sh)
#   - Exit successfully (it intentionally does nothing — nothing to vendor)
#
# Usage: bash test/update-sandcastle-ownership.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0
FAILURES=()

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

echo
echo "update-sandcastle hub-model deprecation tests"
echo "════════════════════════════════════════════════"

# ── 1. Running update-sandcastle prints the deprecation notice ───────────────
echo "── deprecation notice ──"

output="$(DOTFILES="$ROOT" bash "$ROOT/bin/update-sandcastle.sh" 2>&1)"

assert_contains "names sandcastle-hub as source of truth" "arndvs/sandcastle-hub" "$output"
assert_contains "names hub/release.sh as the replacement" "hub/release.sh" "$output"
assert_contains "states the engine is no longer vendored" "no longer vendored" "$output"

# ── 2. Help flag routes to the same notice ───────────────────────────────────
echo ""
echo "── help ──"

help_output="$(DOTFILES="$ROOT" bash "$ROOT/bin/update-sandcastle.sh" --help 2>&1)"

assert_contains "help names the hub" "arndvs/sandcastle-hub" "$help_output"
assert_contains "help names hub/release.sh" "hub/release.sh" "$help_output"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────────"
printf "  %d passed, %d failed\n" "$PASS" "$FAIL"
if (( FAIL > 0 )); then
    echo ""
    echo "  Failures:"
    for f in "${FAILURES[@]}"; do
        echo "    • $f"
    done
    exit 1
fi
