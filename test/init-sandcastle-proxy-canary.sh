#!/usr/bin/env bash
# test/init-sandcastle-proxy-canary.sh — Tests for proxy vs proxyCanary separation (#241).
#
# Validates that init-sandcastle.sh:
#   - Defaults to proxy: true, proxyCanary: false
#   - --with-proxy-canary installs proxy-canary.yml
#   - --no-proxy-canary skips proxy-canary.yml (explicit)
#   - Default init does NOT install proxy-canary.yml
#   - sandcastle.config.json records proxyCanary independently
#   - Existing --with-proxy / --no-proxy behavior unchanged
#
# Usage: bash test/init-sandcastle-proxy-canary.sh
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
assert_file_exists() {
    local label="$1" path="$2"
    if [[ -f "$path" ]]; then _ok "$label"
    else _fail "$label" "file not found: $path"; fi
}
assert_file_not_exists() {
    local label="$1" path="$2"
    if [[ ! -f "$path" ]]; then _ok "$label"
    else _fail "$label" "file should not exist: $path"; fi
}

# ── Helpers ───────────────────────────────────────────────────────────────────
# We test by parsing the script source rather than running it (which needs
# the full dotfiles environment). This is a unit-level check of the arg-parsing
# and config-generation logic.

SCRIPT="bin/init-sandcastle.sh"

echo "── init-sandcastle proxy canary split (#241) ──"
echo ""

# ── 1. Default variable declarations ─────────────────────────────────────────
echo "── defaults ──"

# WITH_PROXY should default to true
proxy_default="$(grep -E '^WITH_PROXY=' "$SCRIPT" | head -1 | cut -d= -f2)"
assert_eq "WITH_PROXY defaults to true" "true" "$proxy_default"

# WITH_PROXY_CANARY should default to false
canary_default="$(grep -E '^WITH_PROXY_CANARY=' "$SCRIPT" | head -1 | cut -d= -f2)"
assert_eq "WITH_PROXY_CANARY defaults to false" "false" "$canary_default"

# ── 2. Arg parsing supports --with-proxy-canary / --no-proxy-canary ──────────
echo ""
echo "── arg parsing ──"

assert_contains "parses --with-proxy-canary" "--with-proxy-canary" "$(cat "$SCRIPT")"
assert_contains "parses --no-proxy-canary" "--no-proxy-canary" "$(cat "$SCRIPT")"

# Existing proxy args still present
assert_contains "parses --with-proxy" "--with-proxy)" "$(cat "$SCRIPT")"
assert_contains "parses --no-proxy" "--no-proxy)" "$(cat "$SCRIPT")"

# ── 3. Config records proxyCanary independently ──────────────────────────────
echo ""
echo "── config generation ──"

# The config template should include both proxy and proxyCanary
config_block="$(sed -n '/cat > sandcastle.config.json/,/CONFIGEOF/p' "$SCRIPT")"
assert_contains "config includes proxy field" '"proxy":' "$config_block"
assert_contains "config includes proxyCanary field" '"proxyCanary":' "$config_block"

# proxyCanary should use WITH_PROXY_CANARY variable
assert_contains "proxyCanary uses WITH_PROXY_CANARY var" 'WITH_PROXY_CANARY' "$config_block"

# ── 4. Proxy canary workflow gated on WITH_PROXY_CANARY ──────────────────────
echo ""
echo "── proxy canary workflow gating ──"

# The proxy monitoring section should check WITH_PROXY_CANARY, not WITH_PROXY
canary_section="$(sed -n '/proxy monitoring workflows/,/^fi$/p' "$SCRIPT" | head -10)"
assert_contains "canary install gated on WITH_PROXY_CANARY" "WITH_PROXY_CANARY" "$canary_section"

# ── 5. Help text mentions proxy canary flags ─────────────────────────────────
echo ""
echo "── help text ──"

help_block="$(sed -n '/--help|-h)/,/exit 0/p' "$SCRIPT")"
assert_contains "help mentions --with-proxy-canary" "proxy-canary" "$help_block"

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
