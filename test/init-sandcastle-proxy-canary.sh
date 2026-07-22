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
json_bool() {
    node -e '
const fs = require("fs");
try {
  const cfg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  process.stdout.write(String(cfg[process.argv[2]]));
} catch {
  process.stdout.write("__missing_or_invalid_json__");
}
' "$1" "$2" || printf '__missing_or_invalid_json__'
}

# ── Helpers ───────────────────────────────────────────────────────────────────
# Source-level checks catch parser/config wiring. Runtime checks below execute
# init-sandcastle.sh in scratch git repos with fake network/package tools so the
# generated config/workflow outputs are validated without touching GitHub or pnpm.

SCRIPT="bin/init-sandcastle.sh"
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t init-sandcastle-proxy-canary)"
trap 'rm -rf "$TMP"' EXIT

FAKE_BIN="$TMP/fake-bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/pnpm" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$FAKE_BIN/gh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$FAKE_BIN/pnpm" "$FAKE_BIN/gh"

run_init_case() {
    local name="$1"; shift
    local repo="$TMP/$name"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" remote add origin "https://github.com/example/$name.git"

    set +e
    (
        cd "$repo"
        DOTFILES="$ROOT" PATH="$FAKE_BIN:$PATH" bash "$ROOT/$SCRIPT" --branch dev --no-artifacts "$@" > "$repo/init.log" 2>&1
    )
    local ec=$?
    set -e
    if [[ "$ec" -ne 0 ]]; then
        echo "init-sandcastle failed for case '$name' (exit $ec). Last 40 log lines:" >&2
        tail -40 "$repo/init.log" >&2 || true
        return "$ec"
    fi

    printf '%s\n' "$repo"
}

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

# ── 6. Runtime output in scratch repos ────────────────────────────────────────
echo ""
echo "── runtime generated outputs ──"

default_repo="$(run_init_case default)"
assert_eq "default init writes proxy=true" "true" "$(json_bool "$default_repo/sandcastle.config.json" proxy)"
assert_eq "default init writes proxyCanary=false" "false" "$(json_bool "$default_repo/sandcastle.config.json" proxyCanary)"
assert_file_not_exists "default init does not install proxy-canary.yml" "$default_repo/.github/workflows/proxy-canary.yml"

with_canary_repo="$(run_init_case with-canary --with-proxy-canary)"
assert_eq "--with-proxy-canary keeps proxy=true" "true" "$(json_bool "$with_canary_repo/sandcastle.config.json" proxy)"
assert_eq "--with-proxy-canary writes proxyCanary=true" "true" "$(json_bool "$with_canary_repo/sandcastle.config.json" proxyCanary)"
assert_file_exists "--with-proxy-canary installs proxy-canary.yml" "$with_canary_repo/.github/workflows/proxy-canary.yml"

with_proxy_repo="$(run_init_case with-proxy --with-proxy)"
assert_eq "--with-proxy alone writes proxy=true" "true" "$(json_bool "$with_proxy_repo/sandcastle.config.json" proxy)"
assert_eq "--with-proxy alone writes proxyCanary=false" "false" "$(json_bool "$with_proxy_repo/sandcastle.config.json" proxyCanary)"
assert_file_not_exists "--with-proxy alone does not install proxy-canary.yml" "$with_proxy_repo/.github/workflows/proxy-canary.yml"

explicit_no_canary_repo="$(run_init_case explicit-no-canary --with-proxy --no-proxy-canary)"
assert_eq "--with-proxy --no-proxy-canary writes proxy=true" "true" "$(json_bool "$explicit_no_canary_repo/sandcastle.config.json" proxy)"
assert_eq "--with-proxy --no-proxy-canary writes proxyCanary=false" "false" "$(json_bool "$explicit_no_canary_repo/sandcastle.config.json" proxyCanary)"
assert_file_not_exists "--with-proxy --no-proxy-canary skips proxy-canary.yml" "$explicit_no_canary_repo/.github/workflows/proxy-canary.yml"

no_proxy_repo="$(run_init_case no-proxy --no-proxy)"
assert_eq "--no-proxy preserves proxy routing opt-out" "false" "$(json_bool "$no_proxy_repo/sandcastle.config.json" proxy)"
assert_eq "--no-proxy leaves proxyCanary=false" "false" "$(json_bool "$no_proxy_repo/sandcastle.config.json" proxyCanary)"
assert_file_not_exists "--no-proxy does not install proxy-canary.yml by default" "$no_proxy_repo/.github/workflows/proxy-canary.yml"

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
