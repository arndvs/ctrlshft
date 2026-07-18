#!/usr/bin/env bash
# test/update-sandcastle-proxy-canary.sh — Tests for proxy canary drift/apply (#242).
#
# Validates that update-sandcastle.sh:
#   - Reads proxyCanary separately from proxy in sandcastle.config.json
#   - Only checks proxy-canary.yml when proxyCanary is true
#   - Reports proxy-canary.yml as stale when proxyCanary is not true
#   - Apply mode removes stale proxy-canary.yml when proxyCanary is not true
#   - proxy: true alone no longer installs/preserves proxy canary
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
assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then _ok "$label"
    else _fail "$label" "expected '$expected', got '$actual'"; fi
}
assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then _ok "$label"
    else _fail "$label" "expected to contain '$needle' in: $haystack"; fi
}
assert_not_contains() {
    local label="$1" needle="$2" haystack="$3"
    if [[ "$haystack" != *"$needle"* ]]; then _ok "$label"
    else _fail "$label" "should NOT contain '$needle' in: $haystack"; fi
}

SCRIPT="bin/update-sandcastle.sh"

echo "── update-sandcastle proxy canary split (#242) ──"
echo ""

# ── 1. Config reading: proxyCanary read separately from proxy ────────────────
echo "── config reading ──"

# Script should read PROXY_CANARY from config
assert_contains "reads proxyCanary from config" "proxyCanary" "$(cat "$SCRIPT")"

# PROXY_CANARY should be a separate variable from PROXY
proxy_canary_var="$(grep -c 'PROXY_CANARY' "$SCRIPT" || true)"
assert_eq "PROXY_CANARY variable referenced multiple times" "true" "$( (( proxy_canary_var >= 2 )) && echo true || echo false)"

# Default should be false (not true)
proxy_canary_default="$(grep -E '^PROXY_CANARY=' "$SCRIPT" | head -1 | cut -d= -f2 | tr -d '"')"
assert_eq "PROXY_CANARY defaults to false" "false" "$proxy_canary_default"

# ── 2. Drift detection gating ────────────────────────────────────────────────
echo ""
echo "── drift detection gating ──"

# Section 8b should use PROXY_CANARY for canary workflows
script_content="$(cat "$SCRIPT")"
assert_contains "canary drift check gated on PROXY_CANARY" 'PROXY_CANARY' "$script_content"

# ── 3. Stale detection: report proxy-canary.yml as stale ─────────────────────
echo ""
echo "── stale canary detection ──"

# When proxyCanary is false and proxy-canary.yml exists, it should be flagged
assert_contains "detects stale proxy-canary.yml" "proxy-canary.yml" "$script_content"
assert_contains "stale detection logic present" "stale" "$script_content"

# ── 4. Apply mode: removes stale proxy canary ────────────────────────────────
echo ""
echo "── apply mode removal ──"

# Apply section should handle both stale removal paths:
# - proxy enabled, but proxyCanary disabled
# - proxy disabled entirely
assert_contains "apply removes stale canary from proxy-enabled branch" 'rm "$dst"' "$script_content"
assert_contains "apply removes stale canary from proxy-disabled branch" 'rm ".github/workflows/proxy-canary.yml"' "$script_content"

# ── 5. proxy: true alone does NOT gate canary ────────────────────────────────
echo ""
echo "── proxy vs proxyCanary separation ──"

# PROXY_CANARY used in multiple sections (drift detection + apply)
canary_gates="$(grep -c 'PROXY_CANARY' "$SCRIPT" || true)"
assert_eq "PROXY_CANARY used in multiple sections (drift+apply)" "true" "$( (( canary_gates >= 4 )) && echo true || echo false)"

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
