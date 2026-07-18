#!/usr/bin/env bash
# test/doc-proxy-canary-accuracy.sh — Verify docs reflect the central canary model (#245).
#
# Acceptance criteria from issue #245:
#   1. shft/README.md documents proxyCanary and opt-in scheduled monitoring
#   2. shft/docs/platform-spec.md no longer says proxy canary is vendored by default
#   3. bin/init-sandcastle.sh --help explains --with-proxy-canary and --no-proxy-canary
#   4. Docs distinguish proxy runtime routing from proxyCanary monitoring ownership
#   5. Docs recommend one canonical scheduled canary in the proxy owner repo
#
# Usage: bash test/doc-proxy-canary-accuracy.sh
set -euo pipefail
ROOT="$(cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$(dirname "$0")/..")" && pwd)"
cd "$ROOT"

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
    local label="$1" needle="$2" file="$3"
    if grep -qF -- "$needle" "$file" 2>/dev/null; then _ok "$label"
    else _fail "$label" "expected '$needle' in $file"; fi
}
assert_not_grep() {
    local label="$1" pattern="$2" file="$3"
    if ! grep -qE "$pattern" "$file" 2>/dev/null; then _ok "$label"
    else _fail "$label" "pattern '$pattern' should NOT be in $file"; fi
}
assert_grep() {
    local label="$1" pattern="$2" file="$3"
    if grep -qE "$pattern" "$file" 2>/dev/null; then _ok "$label"
    else _fail "$label" "pattern '$pattern' not found in $file"; fi
}

README="shft/README.md"
SPEC="shft/docs/platform-spec.md"
INIT="bin/init-sandcastle.sh"

echo "── doc-proxy-canary-accuracy (#245) ──"
echo ""

# ── AC1: shft/README.md documents proxyCanary and opt-in scheduled monitoring ─
echo "── AC1: README documents proxyCanary ──"
assert_contains "README mentions proxyCanary" "proxyCanary" "$README"
assert_contains "README mentions --with-proxy-canary" "--with-proxy-canary" "$README"
assert_grep "README mentions opt-in" "opt.in" "$README"

# ── AC2: platform-spec.md no longer says proxy canary vendored by default ─────
echo ""
echo "── AC2: platform-spec no longer says canary vendored by default ──"
assert_not_grep "spec does not say canary vendored with plain --with-proxy" \
    "proxy-canary.*[Vv]endored.*--with-proxy[)\"]" "$SPEC"
assert_not_grep "spec does not say canary is default on" \
    "proxy-canary.*default on" "$SPEC"

# ── AC3: init --help explains --with-proxy-canary and --no-proxy-canary ───────
echo ""
echo "── AC3: init --help mentions canary flags ──"
help_text="$(DOTFILES="$ROOT" bash "$INIT" --help 2>&1 || true)"
if echo "$help_text" | grep -qF -- "--with-proxy-canary"; then _ok "help mentions --with-proxy-canary"
else _fail "help mentions --with-proxy-canary" "not found in --help output"; fi
if echo "$help_text" | grep -qF -- "--no-proxy-canary"; then _ok "help mentions --no-proxy-canary"
else _fail "help mentions --no-proxy-canary" "not found in --help output"; fi

# ── AC4: Docs distinguish proxy routing from proxyCanary monitoring ───────────
echo ""
echo "── AC4: Docs distinguish proxy routing from canary monitoring ──"
assert_grep "README mentions proxy routing" "proxy.*rout" "$README"
assert_grep "README mentions monitoring" "monitor" "$README"

# ── AC5: Docs recommend one canonical scheduled canary ────────────────────────
echo ""
echo "── AC5: Docs recommend central canary ──"
assert_grep "README recommends canonical or central canary" "canonical|central" "$README"

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
