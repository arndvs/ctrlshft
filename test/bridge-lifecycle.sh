#!/usr/bin/env bash
# test/bridge-lifecycle.sh — Shell regressions for bridge CLI/install lifecycle.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0
FAILURES=()
TMP_DIRS=()

_cleanup() {
    for d in "${TMP_DIRS[@]+"${TMP_DIRS[@]}"}"; do
        [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
    done
}
trap '_cleanup' EXIT INT TERM

_ok() { PASS=$((PASS + 1)); printf "  \033[32m✓\033[0m %s\n" "$1"; }
_fail() { FAIL=$((FAIL + 1)); FAILURES+=("$1: $2"); printf "  \033[31m✗\033[0m %s — %s\n" "$1" "$2"; }

_tmp() {
    TMP=$(mktemp -d 2>/dev/null || mktemp -d -t bridge-lifecycle)
    TMP_DIRS+=("$TMP")
}

_fake_bin() {
    local dir="$1"
    mkdir -p "$dir/bin"
    cat > "$dir/bin/systemctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${SYSTEMCTL_LOG:?}"
exit 0
SH
    chmod +x "$dir/bin/systemctl"
}

_fake_commands() {
    local dir="$1"
    mkdir -p "$dir/bin"
    for cmd in docker systemctl sqlite3 jq srt; do
        cat > "$dir/bin/$cmd" <<'SH'
#!/usr/bin/env bash
exit 0
SH
        chmod +x "$dir/bin/$cmd"
    done
}

_fake_venv_python() {
    local path="$1"
    mkdir -p "$(dirname "$path")"
    cat > "$path" <<'SH'
#!/usr/bin/env bash
exit 0
SH
    chmod +x "$path"
}

_assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if grep -qF "$needle" <<<"$haystack"; then
        _ok "$label"
    else
        _fail "$label" "missing '$needle' in: $haystack"
    fi
}

echo ""
echo "Bridge lifecycle shell tests"
echo "════════════════════════════════════════════════"

echo ""
echo "── ctrl bridge worker count ──"
for subcmd in start restart; do
    _tmp
    tmp="$TMP"
    _fake_bin "$tmp"
    out=""
    ec=0
    SYSTEMCTL_LOG="$tmp/systemctl.log" PATH="$tmp/bin:$PATH" DOTFILES="$ROOT" HOME="$tmp/home" WORKER_COUNT=2 \
        bash "$ROOT/bin/ctrl" bridge "$subcmd" >"$tmp/out" 2>&1 || ec=$?
    out=$(<"$tmp/out")
    [[ "$ec" -ne 0 ]] && _ok "ctrl bridge $subcmd refuses WORKER_COUNT=2" || _fail "ctrl bridge $subcmd refuses WORKER_COUNT=2" "exit $ec"
    _assert_contains "$out" "WORKER_COUNT must be exactly 1" "ctrl bridge $subcmd explains WORKER_COUNT limit"
    [[ ! -s "$tmp/systemctl.log" ]] && _ok "ctrl bridge $subcmd refuses before touching systemd" || _fail "ctrl bridge $subcmd refuses before touching systemd" "$(<"$tmp/systemctl.log")"
done

_tmp
tmp="$TMP"
_fake_bin "$tmp"
SYSTEMCTL_LOG="$tmp/systemctl.log" PATH="$tmp/bin:$PATH" DOTFILES="$ROOT" HOME="$tmp/home" WORKER_COUNT=1 \
    bash "$ROOT/bin/ctrl" bridge start >"$tmp/out" 2>&1
if grep -qx -- "--user start bridge-webhook.service" "$tmp/systemctl.log" \
    && grep -qx -- "--user start bridge-worker@1.service" "$tmp/systemctl.log" \
    && [[ "$(wc -l < "$tmp/systemctl.log" | tr -d ' ')" == "2" ]]; then
    _ok "ctrl bridge start starts exactly one worker"
else
    _fail "ctrl bridge start starts exactly one worker" "$(<"$tmp/systemctl.log")"
fi

echo ""
echo "── bridge-install EnvironmentFile validation ──"
_tmp
tmp="$TMP"
_fake_commands "$tmp"
mkdir -p "$tmp/dotfiles/secrets/.venv/bin" "$tmp/bridge"
_fake_venv_python "$tmp/dotfiles/secrets/.venv/bin/python"
cat > "$tmp/dotfiles/secrets/.env.agent" <<'ENV'
BRIDGE_REPO_ALLOWLIST=arndvs/ctrlshft
ENV
cat > "$tmp/dotfiles/secrets/.env.secrets" <<'ENV'
GITHUB_APP_ID=123
GITHUB_APP_INSTALLATION_ID=456
GITHUB_APP_PRIVATE_KEY_B64=abc
ENV
cat > "$tmp/dotfiles/secrets/.env.bridge" <<'ENV'
WEBHOOK_SECRET=12345678901234567890123456789012
ENV
PATH="$tmp/bin:$PATH" CTRLSHFT_HOME="$tmp/dotfiles" BRIDGE_ROOT="$tmp/bridge" HOME="$tmp/home" \
    bash "$ROOT/bin/bridge-install.sh" --validate >"$tmp/install.out" 2>&1 \
    && _ok "bridge-install --validate reads EnvironmentFile contents without exported secrets" \
    || _fail "bridge-install --validate reads EnvironmentFile contents without exported secrets" "$(<"$tmp/install.out")"

_tmp
tmp="$TMP"
_fake_commands "$tmp"
mkdir -p "$tmp/dotfiles/secrets/.venv/bin" "$tmp/bridge"
_fake_venv_python "$tmp/dotfiles/secrets/.venv/bin/python"
cat > "$tmp/dotfiles/secrets/.env.agent" <<'ENV'
BRIDGE_REPO_ALLOWLIST=arndvs/ctrlshft
ENV
cat > "$tmp/dotfiles/secrets/.env.secrets" <<'ENV'
GITHUB_APP_ID=123
GITHUB_APP_INSTALLATION_ID=456
GITHUB_APP_PRIVATE_KEY_B64=abc
ENV
cat > "$tmp/dotfiles/secrets/.env.bridge" <<'ENV'
WEBHOOK_SECRET=
ENV
ec=0
PATH="$tmp/bin:$PATH" CTRLSHFT_HOME="$tmp/dotfiles" BRIDGE_ROOT="$tmp/bridge" HOME="$tmp/home" \
    bash "$ROOT/bin/bridge-install.sh" --validate >"$tmp/install.out" 2>&1 || ec=$?
if [[ "$ec" -ne 0 ]] && grep -qF "WEBHOOK_SECRET is missing or empty" "$tmp/install.out"; then
    _ok "bridge-install --validate fails empty webhook EnvironmentFile value"
else
    _fail "bridge-install --validate fails empty webhook EnvironmentFile value" "exit $ec: $(<"$tmp/install.out")"
fi

echo ""
echo "════════════════════════════════════════════════"
printf "  \033[32m%d passed\033[0m  \033[31m%d failed\033[0m\n" "$PASS" "$FAIL"
if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo ""
    echo "  Failures:"
    for f in "${FAILURES[@]}"; do printf "    \033[31m✗\033[0m %s\n" "$f"; done
    echo ""
    exit 1
fi
echo ""
exit 0
