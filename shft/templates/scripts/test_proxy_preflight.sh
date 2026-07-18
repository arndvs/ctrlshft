#!/usr/bin/env bash
#
# test_proxy_preflight.sh — hermetic tests for proxy_preflight.sh.
#
# Stubs curl via PATH so proxy readiness/model checks run offline.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROBE="$SCRIPT_DIR/proxy_preflight.sh"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf "  \033[32m✓\033[0m %s\n" "$1"; }
fail() { FAIL=$((FAIL + 1)); printf "  \033[31m✗\033[0m %s\n" "$1"; }

TMPDIR_ROOT=$(mktemp -d)
cleanup() { rm -rf "$TMPDIR_ROOT"; }
trap cleanup EXIT

STUB_DIR="$TMPDIR_ROOT/stubs"
WORK_DIR="$TMPDIR_ROOT/work"
mkdir -p "$STUB_DIR" "$WORK_DIR"

cat > "$STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
out=""
prev=""
auth=""
for arg in "$@"; do
  [ "$prev" = "-o" ] && out="$arg"
  if [ "$prev" = "-H" ] && [[ "$arg" == Authorization:* ]]; then
    auth="$arg"
  fi
  prev="$arg"
done
url="${@: -1}"
if [[ "$url" == */health/readiness ]]; then
  [ -n "$out" ] && printf '%s' "${STUB_READY_BODY:-OK}" > "$out"
  printf '%s' "${STUB_READY_CODE:-200}"
elif [[ "$url" == */v1/models ]]; then
  [ -n "${STUB_AUTH_CAPTURE:-}" ] && printf '%s' "$auth" > "$STUB_AUTH_CAPTURE"
  if [ -n "$out" ]; then
    if [ -n "${STUB_MODELS_BODY+x}" ]; then
      printf '%s' "$STUB_MODELS_BODY" > "$out"
    else
      printf '%s' '{"data":[{"id":"claude-sonnet-4-6"}]}' > "$out"
    fi
  fi
  printf '%s' "${STUB_MODELS_CODE:-200}"
else
  printf '404'
fi
STUB
chmod +x "$STUB_DIR/curl"

write_config() {
  printf '{"model":"%s"}\n' "${1:-claude-sonnet-4-6}" > "$WORK_DIR/sandcastle.config.json"
}

run_preflight() {
  local out_file="$TMPDIR_ROOT/github-output"
  rm -f "$out_file"
  (
    cd "$WORK_DIR"
    GITHUB_OUTPUT="$out_file" PATH="$STUB_DIR:$PATH" bash "$PROBE" >/dev/null
  )
  cat "$out_file"
}

assert_field() {
  local label="$1" output="$2" key="$3" expected="$4"
  if printf '%s\n' "$output" | grep -qx "$key=$expected"; then
    pass "$label"
  else
    fail "$label"
  fi
}

echo "── proxy_preflight.sh tests ──"

write_config
out=$(ANTHROPIC_BASE_URL="" ANTHROPIC_AUTH_TOKEN="" run_preflight)
assert_field "direct provider mode runs" "$out" "should_run" "true"
assert_field "direct provider mode reason" "$out" "reason" "direct-provider"

out=$(ANTHROPIC_BASE_URL="https://proxy.test/v1" ANTHROPIC_AUTH_TOKEN="" run_preflight)
assert_field "missing proxy token skips" "$out" "should_run" "false"
assert_field "missing proxy token reason" "$out" "reason" "missing-proxy-token"

out=$(ANTHROPIC_BASE_URL="https://proxy.test/v1" ANTHROPIC_AUTH_TOKEN="secret-token" STUB_READY_CODE=503 run_preflight)
assert_field "readiness failure skips" "$out" "should_run" "false"
assert_field "readiness failure reason" "$out" "reason" "proxy-not-ready"

auth_capture="$TMPDIR_ROOT/auth-header.txt"
out=$(ANTHROPIC_BASE_URL="https://proxy.test/v1" ANTHROPIC_AUTH_TOKEN="secret-token" STUB_AUTH_CAPTURE="$auth_capture" run_preflight)
assert_field "available model runs" "$out" "should_run" "true"
assert_field "available model reason" "$out" "reason" "ok"
if [ "$(cat "$auth_capture" 2>/dev/null || true)" = "Authorization: Bearer secret-token" ] && ! printf '%s\n' "$out" | grep -qF "secret-token"; then
  pass "models probe sends bearer token without emitting it"
else
  fail "models probe auth header"
fi

out=$(ANTHROPIC_BASE_URL="https://proxy.test/v1" ANTHROPIC_AUTH_TOKEN="secret-token" STUB_MODELS_BODY='{"data":[{"id":"other-model"}]}' run_preflight)
assert_field "missing configured model skips" "$out" "should_run" "false"
assert_field "missing configured model reason" "$out" "reason" "model-unavailable"

out=$(ANTHROPIC_BASE_URL="https://proxy.test/v1" ANTHROPIC_AUTH_TOKEN="secret-token" STUB_MODELS_CODE=401 run_preflight)
assert_field "models auth failure skips" "$out" "should_run" "false"
assert_field "models auth failure reason" "$out" "reason" "proxy-auth-failed"

out=$(ANTHROPIC_BASE_URL="https://proxy.test/v1" ANTHROPIC_AUTH_TOKEN="secret-token" STUB_MODELS_CODE=404 run_preflight)
assert_field "models probe unavailable still runs after readiness" "$out" "should_run" "true"
assert_field "models probe unavailable reason" "$out" "reason" "models-probe-unavailable"

printf '{}\n' > "$WORK_DIR/sandcastle.config.json"
out=$(ANTHROPIC_BASE_URL="https://proxy.test/v1" ANTHROPIC_AUTH_TOKEN="secret-token" run_preflight)
assert_field "missing model config skips" "$out" "should_run" "false"
assert_field "missing model config reason" "$out" "reason" "missing-model"

echo ""
printf "  \033[32m%d passed\033[0m  \033[31m%d failed\033[0m\n" "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
