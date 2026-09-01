#!/usr/bin/env bash
# test/update-sandcastle-proxy-canary.sh — Verify update-sandcastle reports hub-model deprecation.
#
# The engine is no longer vendored (hub model). update-sandcastle.sh is a
# deprecated stub that must print the deprecation notice naming the hub and
# the hub release path. The old proxy-canary drift/apply behavior is retired
# with the vendoring model.
#
# Usage: bash test/update-sandcastle-proxy-canary.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$(dirname "$0")/..")"

# ── Test harness ──────────────────────────────────────────────────────────────
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
assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then _ok "$label"
    else _fail "$label" "expected to contain '$needle' in: $haystack"; fi
}

SCRIPT="bin/update-sandcastle.sh"

echo "── update-sandcastle hub-model deprecation (#242) ──"
echo ""

# ── 1. Running update-sandcastle prints the deprecation notice ───────────────
echo "── deprecation notice ──"

output="$(DOTFILES="$(pwd)" bash "$SCRIPT" 2>&1)"

assert_contains "names ctrlshft-hub as source of truth" "arndvs/ctrlshft-hub" "$output"
assert_contains "names hub/release.sh as the replacement" "hub/release.sh" "$output"
assert_contains "states the engine is no longer vendored" "no longer vendored" "$output"

# ── 2. Help flag routes to the same notice ───────────────────────────────────
echo ""
echo "── help ──"

help_output="$(DOTFILES="$(pwd)" bash "$SCRIPT" --help 2>&1)"

assert_contains "help names the hub" "arndvs/ctrlshft-hub" "$help_output"
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
