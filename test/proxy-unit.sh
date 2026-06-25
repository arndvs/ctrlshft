#!/usr/bin/env bash
# test/proxy-unit.sh — Unit tests for proxy helper functions.
#
# Tests the pure-logic helpers extracted from shft and _proxy_env.sh:
#   _proxy_get / _proxy_set   — JSON state read/write
#   _proxy_load_key            — env var extraction
#   _proxy_running             — PID-first, health-fallback detection
#   _proxy_env_get             — jq > python > grep cascade
#   proxy stop                 — PID validation before kill
#   shft status                — port defaulting
#
# These tests use a temp directory for state, no real daemon required.
# Usage: bash test/proxy-unit.sh
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
assert_exit() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then _ok "$label"
    else _fail "$label" "expected exit $expected, got $actual"; fi
}
extract_function() {
    local file="$1" name="$2"
    awk -v name="$name" '
        $0 ~ "^" name "\\(\\)" { in_fn=1 }
        in_fn && $0 ~ /^[[:alnum:]_]+\(\)[[:space:]]*\{/ && $0 !~ "^" name "\\(\\)" { exit }
        in_fn { print }
        in_fn && /^}[[:space:]]*$/ { exit }
    ' "$file"
}

# ── Temp environment ──────────────────────────────────────────────────────────
TMP=$(mktemp -d)
# Resolve to canonical path (MINGW mktemp returns /tmp/... but tools resolve to C:/...)
TMP=$(cd "$TMP" && pwd)
trap 'rm -rf "$TMP"' EXIT

# Source _lib.sh for green/yellow/red (needed by shft helpers)
source "$PWD/bin/_lib.sh"

# ── Set up the shft globals the helpers need ──────────────────────────────────
PROXY_STATE_DIR="$TMP/.shft"
PROXY_STATE_FILE="$PROXY_STATE_DIR/proxy.json"
PROXY_LOG_FILE="$PROXY_STATE_DIR/proxy.log"
PROXY_DEFAULT_PORT=4000
DOTFILES="$PWD"
VENV_DIR="$PWD/secrets/.venv"
if find_python 2>/dev/null; then SHFT_PYTHON="$PYTHON"; else SHFT_PYTHON=""; fi

# ═══════════════════════════════════════════════════════════════════════════════
echo
echo "Proxy unit tests"
echo "════════════════════════════════════════════════"

# ── Source the helper functions from shft (stop before CMD dispatch) ───────────
# We can't source the whole script (it runs main), so extract the functions.
# Strategy: define the functions inline by sourcing just the function block.

# Shared proxy health helpers are now in a dedicated module.
source shft/_proxy_health.sh

# _proxy_get / _proxy_set / _proxy_running / _proxy_load_key
# These are defined in shft between "# ── Proxy state helpers" and "# Require gh CLI"
eval "$(sed -n '/^# ── Proxy state helpers/,/^# Require gh CLI/{ /^# Require gh CLI/d; p; }' shft/shft)"

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "_proxy_set + _proxy_get — JSON state round-trip"
echo "────────────────────────────────────────────────"

mkdir -p "$PROXY_STATE_DIR"
_proxy_set "enabled" "true"
assert_eq "set+get boolean" "true" "$(_proxy_get enabled)"

_proxy_set "port" "4000"
assert_eq "set+get number" "4000" "$(_proxy_get port)"

_proxy_set "dir" "proxy-dir-value"
assert_eq "set+get string" "proxy-dir-value" "$(_proxy_get dir)"

_proxy_set "pid" "12345"
assert_eq "set+get pid" "12345" "$(_proxy_get pid)"

# Missing field returns empty
assert_eq "get missing field" "" "$(_proxy_get nonexistent)"

# Missing state file returns empty
rm -f "$PROXY_STATE_FILE"
assert_eq "get from missing file" "" "$(_proxy_get enabled)"

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "_proxy_load_key — extracts only LITELLM_MASTER_KEY"
echo "────────────────────────────────────────────────"

_fake_proxy_dir="$TMP/fake-proxy"
mkdir -p "$_fake_proxy_dir"

# Happy path
cat > "$_fake_proxy_dir/.env" <<'EOF'
LITELLM_MASTER_KEY=sk-test-key-abc123
OTHER_SECRET=should-not-leak
DATABASE_URL=postgres://localhost/db
EOF
_key=$(_proxy_load_key "$_fake_proxy_dir")
assert_eq "extracts master key" "sk-test-key-abc123" "$_key"

# Does NOT leak other vars
assert_not_contains "no OTHER_SECRET" "should-not-leak" "$_key"

# Missing .env
_missing_output=$(_proxy_load_key "$TMP/nonexistent" 2>&1 || true)
assert_contains "missing .env errors" "not found" "$_missing_output"

# Empty key
cat > "$_fake_proxy_dir/.env" <<'EOF'
OTHER_VAR=something
EOF
_empty_key_output=$(_proxy_load_key "$_fake_proxy_dir" 2>&1 || true)
assert_contains "empty key errors" "LITELLM_MASTER_KEY not found or empty" "$_empty_key_output"

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "_proxy_running — PID check first, health fallback"
echo "────────────────────────────────────────────────"

# With a valid PID (use our own PID — guaranteed alive)
mkdir -p "$PROXY_STATE_DIR"
_proxy_set "pid" "$$"
_proxy_set "port" "19999"  # unlikely to have anything on this port
ec=0; _proxy_running || ec=$?
assert_eq "own PID → running" "0" "$ec"

# With a dead PID and no health endpoint
_proxy_set "pid" "99999999"
_proxy_set "port" "19999"
ec=0; _proxy_running || ec=$?
if [[ $ec -ne 0 ]]; then _ok "dead PID + no health → not running (exit $ec)"
else _fail "dead PID + no health → not running" "expected non-zero exit, got 0"; fi

# With empty PID and no health endpoint
_proxy_set "pid" ""
_proxy_set "port" "19999"
ec=0; _proxy_running || ec=$?
if [[ $ec -ne 0 ]]; then _ok "empty PID + no health → not running (exit $ec)"
else _fail "empty PID + no health → not running" "expected non-zero exit, got 0"; fi

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "proxy stop — PID validation before kill"
echo "────────────────────────────────────────────────"

# Simulate the proxy stop logic (extracted from shft)
_test_proxy_stop() {
    local _pid
    _pid=$(_proxy_get "pid")
    if [[ -n "$_pid" ]] && kill -0 "$_pid" 2>/dev/null; then
        echo "WOULD_KILL:$_pid"
    elif _proxy_running; then
        echo "STALE_PID"
    else
        echo "NOT_RUNNING"
    fi
}

# Empty PID should NOT attempt kill
_proxy_set "pid" ""
_proxy_set "port" "19999"
_stop_result=$(_test_proxy_stop)
assert_eq "stop with empty PID → not running" "NOT_RUNNING" "$_stop_result"

# Dead PID should NOT attempt kill
_proxy_set "pid" "99999999"
_proxy_set "port" "19999"
_stop_result=$(_test_proxy_stop)
assert_eq "stop with dead PID → not running" "NOT_RUNNING" "$_stop_result"

# Valid PID reports it would kill (not actually killing)
_proxy_set "pid" "$$"
_proxy_set "port" "19999"
_stop_result=$(_test_proxy_stop)
assert_eq "stop with valid PID → would kill" "WOULD_KILL:$$" "$_stop_result"

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "status port — defaults to PROXY_DEFAULT_PORT"
echo "────────────────────────────────────────────────"

# Port set
_proxy_set "port" "5555"
_port=$(_proxy_get "port")
_port="${_port:-$PROXY_DEFAULT_PORT}"
assert_eq "explicit port used" "5555" "$_port"

# Port empty (the bug we fixed)
_proxy_set "port" ""
_port=$(_proxy_get "port")
_port="${_port:-$PROXY_DEFAULT_PORT}"
assert_eq "empty port defaults to 4000" "4000" "$_port"

# Port missing from state
rm -f "$PROXY_STATE_FILE"
_port=$(_proxy_get "port")
_port="${_port:-$PROXY_DEFAULT_PORT}"
assert_eq "missing port defaults to 4000" "4000" "$_port"

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "_proxy_env_get — jq > python > grep cascade"
echo "────────────────────────────────────────────────"

# Set up state for _proxy_env_get (uses $_PROXY_STATE, not $PROXY_STATE_FILE)
_PROXY_STATE="$TMP/env-test-proxy.json"
cat > "$_PROXY_STATE" <<'EOF'
{
  "enabled": true,
  "port": 4000,
  "dir": "/home/user/proxy",
  "pid": "12345"
}
EOF

# Source _proxy_env_get from _proxy_env.sh
eval "$(extract_function shft/_proxy_env.sh _proxy_env_get)"

assert_eq "env_get enabled" "true" "$(_proxy_env_get enabled)"
assert_eq "env_get port" "4000" "$(_proxy_env_get port)"
assert_eq "env_get dir" "/home/user/proxy" "$(_proxy_env_get dir)"
assert_eq "env_get pid" "12345" "$(_proxy_env_get pid)"
assert_eq "env_get missing" "" "$(_proxy_env_get nonexistent)"

# Missing file
_PROXY_STATE="$TMP/does-not-exist.json"
assert_eq "env_get missing file" "" "$(_proxy_env_get enabled)"

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "Health endpoint consistency — all use /health/readiness"
echo "────────────────────────────────────────────────"

# Verify no stale /health (without /readiness) in the proxy scripts
_bad_health=$(grep -n '/health"' shft/_proxy_env.sh shft/shft 2>/dev/null | grep -v '/health/readiness' | grep -v '^#' | grep -v '# ' || true)
if [[ -z "$_bad_health" ]]; then
    _ok "no bare /health endpoints (all use /health/readiness)"
else
    _fail "found bare /health endpoint" "$_bad_health"
fi

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "set -a; source .env — replaced by _proxy_load_key"
echo "────────────────────────────────────────────────"

# The old pattern leaked all env vars. Verify it's gone from the proxy start command.
_set_a_hits=$(grep -n 'set -a' shft/shft 2>/dev/null || true)
if [[ -z "$_set_a_hits" ]]; then
    _ok "no 'set -a' in shft (uses _proxy_load_key instead)"
else
    _fail "found 'set -a' in shft" "$_set_a_hits"
fi

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "_require_srt/_require_docker gating — WSL/MSYS skip"
echo "────────────────────────────────────────────────"

# Verify the afk command section has the WSL/MSYS gate
_afk_block=$(sed -n '/^    afk)/,/^    ;;$/p' shft/shft)
assert_contains "afk has WSL check" "microsoft /proc/version" "$_afk_block"
assert_contains "afk has MSYS check" "uname -o" "$_afk_block"
assert_contains "afk conditional _require_srt" "_require_srt" "$_afk_block"
assert_contains "afk conditional _require_docker" "_require_docker" "$_afk_block"

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "bridge/worker.py — git_credential_env spread order"
echo "────────────────────────────────────────────────"

# The fix: git_credential_env() is spread BEFORE PATH so our PATH wins
_worker_env_block=$(sed -n '/env = {/,/^    }/p' bridge/worker.py)
# git_credential_env must come before PATH
_cred_line=$(echo "$_worker_env_block" | grep -n 'git_credential_env' | head -1 | cut -d: -f1)
_path_line=$(echo "$_worker_env_block" | grep -n '"PATH"' | head -1 | cut -d: -f1)
if [[ -n "$_cred_line" ]] && [[ -n "$_path_line" ]] && [[ "$_cred_line" -lt "$_path_line" ]]; then
    _ok "git_credential_env spread before PATH (PATH wins)"
else
    _fail "git_credential_env must be spread BEFORE PATH" "cred line=$_cred_line, path line=$_path_line"
fi

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "curl timeouts — _proxy_running has --max-time + --connect-timeout"
echo "────────────────────────────────────────────────"

_running_fn=$(extract_function shft/shft _proxy_running)
assert_contains "running fn delegates to _proxy_health_ok" "_proxy_health_ok" "$_running_fn"

_running_health_helper=$(extract_function shft/_proxy_health.sh _proxy_health_ok)
assert_contains "health helper has --max-time" "--max-time" "$_running_health_helper"
assert_contains "health helper has --connect-timeout" "--connect-timeout" "$_running_health_helper"

_shft_sources_helper=$(grep -n '_proxy_health.sh' shft/shft || true)
assert_contains "shft sources shared proxy helper" "_proxy_health.sh" "$_shft_sources_helper"

# Same in _proxy_env.sh via _proxy_health_ok helper
_env_daemon_check=$(sed -n '/Verify daemon is running/,/^fi$/p' shft/_proxy_env.sh)
assert_contains "env.sh daemon check uses _proxy_health_ok" "_proxy_health_ok" "$_env_daemon_check"
_env_health_helper=$(extract_function shft/_proxy_health.sh _proxy_health_ok)
assert_contains "env.sh health helper has --max-time" "--max-time" "$_env_health_helper"

_env_sources_helper=$(grep -n '_proxy_health.sh' shft/_proxy_env.sh || true)
assert_contains "env.sh sources shared proxy helper" "_proxy_health.sh" "$_env_sources_helper"

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "_proxy_env.sh — python shim guard"
echo "────────────────────────────────────────────────"

_env_get_fn=$(extract_function shft/_proxy_env.sh _proxy_env_get)
assert_contains "validates python3 with --version" "python3 --version" "$_env_get_fn"
assert_contains "validates python with --version" "python --version" "$_env_get_fn"
assert_contains "prefers jq first" "command -v jq" "$_env_get_fn"

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "_proxy_running comment — says PID-first"
echo "────────────────────────────────────────────────"

_running_comment=$(grep -B1 '_proxy_running()' shft/shft | head -1)
assert_contains "comment says PID" "PID" "$_running_comment"
assert_not_contains "no misleading PID-based" "PID-based)" "$_running_comment"

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "AFK lock scoping — repo-specific lock path (no global static lock)"
echo "────────────────────────────────────────────────"

_shft_lock_constants=$(sed -n '/^# ── Constants/,/^# ── Helper functions/p' shft/shft)
assert_contains "shft defines LOCK_BASE_DIR" "LOCK_BASE_DIR" "$_shft_lock_constants"
assert_contains "shft lock path includes hash id" "shft-afk-" "$_shft_lock_constants"
_shft_main_lock=$(echo "$_shft_lock_constants" | grep '^LOCK_DIR=' || true)
if [[ -n "$_shft_main_lock" ]]; then
    _ok "shft defines main LOCK_DIR"
    assert_not_contains "shft main lock dir is not legacy static /tmp lock" "/tmp/shft-afk.lock" "$_shft_main_lock"
else
    _fail "shft defines main LOCK_DIR" "LOCK_DIR declaration missing"
fi

_afk_lock_decl=$(grep -n '^LOCKDIR=' shft/afk.sh || true)
assert_contains "afk lockdir consumes SHFT_LOCK_DIR" "SHFT_LOCK_DIR" "$_afk_lock_decl"
assert_contains "afk lockdir has TMPDIR fallback" '${TMPDIR:-/tmp}/shft-afk.lock' "$_afk_lock_decl"
assert_not_contains "afk lockdir is not hardcoded static /tmp" 'LOCKDIR="/tmp/shft-afk.lock"' "$_afk_lock_decl"

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "AFK process control — run-state, fail-closed proxy, and hard stop"
echo "────────────────────────────────────────────────"

_shft_constants=$(sed -n '/^# ── Constants/,/^# ── Helper functions/p' shft/shft)
assert_contains "shft defines run-state file" "RUN_STATE_FILE" "$_shft_constants"
assert_contains "shft run-state file is repo-scoped" 'shft-run-${_SHFT_LOCK_ID}.json' "$_shft_constants"
assert_not_contains "shft run-state file is not global" 'shft-run.json' "$_shft_constants"

_lock_identity_fn=$(extract_function shft/shft _shft_lock_identity)
assert_contains "lock identity uses git common dir" "--git-common-dir" "$_lock_identity_fn"

_running_fn=$(extract_function shft/shft _shft_running)
assert_contains "running checks run-state worker pid" "worker_pid" "$_running_fn"
assert_contains "running still checks lock dir" "LOCK_DIR" "$_running_fn"
assert_contains "running scopes pid fallback to tracked lock" '_tracked_lock_dir" == "$LOCK_DIR' "$_running_fn"

_run_state_get_fn=$(extract_function shft/shft _run_state_get)
assert_contains "run-state get has grep fallback" "_run_state_get_grep" "$_run_state_get_fn"
assert_contains "run-state python parse failure exits non-zero" "sys.exit(1)" "$_run_state_get_fn"

_run_state_set_fn=$(extract_function shft/shft _run_state_set)
assert_contains "run-state set has jq fallback" "command -v jq" "$_run_state_set_fn"
assert_contains "run-state set has shell fallback" "_escaped_value" "$_run_state_set_fn"
assert_contains "run-state set preserves existing state without json merger" '[[ -f "$RUN_STATE_FILE" ]]' "$_run_state_set_fn"
assert_contains "run-state set warns when update skipped" "Run-state update skipped" "$_run_state_set_fn"

_kill_tree_fn=$(extract_function shft/shft _kill_afk_tree)
assert_contains "kill tree escalates to SIGKILL" "kill -KILL" "$_kill_tree_fn"
assert_contains "kill tree verifies live pids" "kill -0" "$_kill_tree_fn"

_collect_descendants_fn=$(extract_function shft/shft _collect_descendant_pids)
assert_contains "descendant collector filters non-numeric ps rows" 'pid !~ /^[0-9]+$/' "$_collect_descendants_fn"
assert_contains "descendant collector builds child table once" "children[ppid]" "$_collect_descendants_fn"
assert_contains "descendant collector walks descendants in awk" "stack_len" "$_collect_descendants_fn"
assert_not_contains "descendant collector does not recurse through ps" 'while IFS= read' "$_collect_descendants_fn"

_validate_fn=$(extract_function shft/shft _validate_afk)
assert_contains "proxy down fails closed" "AFK will not start" "$_validate_fn"
assert_contains "proxy validation exits non-zero" "exit 1" "$_validate_fn"
assert_contains "proxy validation waits for readiness" "_proxy_wait_healthy" "$_validate_fn"
assert_contains "proxy validation honors wait env" "SHFT_PROXY_HEALTH_WAIT_SECONDS" "$_validate_fn"

_dirty_guard_fn=$(extract_function shft/shft _shft_require_clean_for_afk)
assert_contains "dirty guard explains worktree mode" "shft afk --worktree" "$_dirty_guard_fn"
_dirty_check_fn=$(extract_function shft/shft _shft_working_tree_dirty)
assert_contains "dirty check includes untracked files" "git status --porcelain" "$_dirty_check_fn"

_canonical_dir_fn=$(extract_function shft/shft _shft_canonical_dir)
assert_contains "canonical dir resolves physical path" "cd -P" "$_canonical_dir_fn"
assert_contains "canonical dir prints physical path" "pwd -P" "$_canonical_dir_fn"
assert_contains "canonical dir normalizes Windows paths" "cygpath -u" "$_canonical_dir_fn"
eval "$_canonical_dir_fn"
_tmp_physical=$(cd -P "$TMP" && pwd -P)
_tmp_canonical=$(_shft_canonical_dir "$TMP")
assert_eq "canonical dir resolves absolute temp path" "$_tmp_physical" "$_tmp_canonical"
if command -v cygpath &>/dev/null; then
    _tmp_windows_forward=$(cygpath -m "$TMP")
    _tmp_windows_backslash=$(cygpath -w "$TMP")
    assert_eq "canonical dir accepts Windows forward-slash path" "$_tmp_physical" "$(_shft_canonical_dir "$_tmp_windows_forward")"
    assert_eq "canonical dir accepts Windows backslash path" "$_tmp_physical" "$(_shft_canonical_dir "$_tmp_windows_backslash")"
fi

_create_worktree_fn=$(extract_function shft/shft _shft_create_afk_worktree)
assert_contains "worktree creation uses git worktree" "git worktree add" "$_create_worktree_fn"
assert_contains "worktree branch is per run" 'afk/$_branch_suffix' "$_create_worktree_fn"
assert_contains "targeted worktree branch names issue" 'issue-${_target_issue}' "$_create_worktree_fn"
assert_contains "worktree branch suffix includes PID uniqueness" '$$' "$_create_worktree_fn"
assert_contains "worktree lives in runtime lane" "_shft_worktree_base_dir" "$_create_worktree_fn"

_worktrees_remove_fn=$(extract_function shft/shft _shft_worktree_remove)
assert_contains "worktree remove blocks active run" "Refusing to remove active AFK worktree" "$_worktrees_remove_fn"
assert_contains "worktree remove canonicalizes requested path" '_canonical_path="$(_shft_canonical_dir "$_path")"' "$_worktrees_remove_fn"
assert_contains "worktree remove canonicalizes active path" '_canonical_active_worktree="$(_shft_canonical_dir "$_active_worktree"' "$_worktrees_remove_fn"
assert_contains "worktree remove protects dirty trees" "status --porcelain" "$_worktrees_remove_fn"

_stop_block=$(sed -n '/^    stop)/,/^        ;;$/p' shft/shft)
assert_contains "stop supports --kill" "--kill" "$_stop_block"
assert_contains "stop delegates to kill tree" "_kill_afk_tree" "$_stop_block"
assert_contains "stop kill fails non-zero when kill tree fails" "exit 1" "$_stop_block"
assert_contains "stop uses tracked lock dir" "lock_dir" "$_stop_block"
assert_contains "stop removes tracked lock dir" 'rmdir "$_lock_dir"' "$_stop_block"
assert_contains "graceful stop mentions hard kill" "shft stop --kill" "$_stop_block"

_status_block=$(sed -n '/^    status)/,/^        ;;$/p' shft/shft)
assert_contains "status shows worker pid" "Worker:" "$_status_block"
assert_contains "status detects orphaned process" "orphaned AFK process" "$_status_block"
assert_contains "status displays tracked lock when scoped lock missing" "_display_lock_dir=\"\$_tracked_lock_dir\"" "$_status_block"
assert_contains "status shows AFK worktree path" "Worktree:" "$_status_block"
assert_contains "status shows AFK worktree branch" "Branch:" "$_status_block"

_afk_command_block=$(sed -n '/^    afk)/,/^        ;;$/p' shft/shft)
assert_contains "shft passes scoped run-state to afk" "SHFT_RUN_STATE_FILE" "$_afk_command_block"
assert_contains "afk supports worktree flag" "--worktree" "$_afk_command_block"
assert_contains "afk current checkout dirty guard" "_shft_require_clean_for_afk" "$_afk_command_block"
assert_contains "afk creates isolated worktree" "_shft_create_afk_worktree" "$_afk_command_block"
assert_contains "afk passes isolated flag" "SHFT_ISOLATED_WORKTREE" "$_afk_command_block"
assert_contains "afk runs from selected cwd" 'cd "$_afk_cwd"' "$_afk_command_block"

_worktrees_block=$(sed -n '/^    worktrees|worktree)/,/^        ;;$/p' shft/shft)
assert_contains "worktrees command lists" "_shft_worktrees_list" "$_worktrees_block"
assert_contains "worktrees command removes" "_shft_worktree_remove" "$_worktrees_block"

_afk_state_writes=$(grep -n '_run_state_set' shft/afk.sh || true)
assert_contains "afk records worker pid" "worker_pid" "$_afk_state_writes"
assert_contains "afk records current iteration" "current_iteration" "$_afk_state_writes"
assert_contains "afk records stderr log" "current_stderr_log" "$_afk_state_writes"
assert_contains "afk records worktree path" "worktree_path" "$_afk_state_writes"
assert_contains "afk records worktree branch" "worktree_branch" "$_afk_state_writes"

_afk_run_state_decl=$(grep -n 'RUN_STATE_FILE=' shft/afk.sh || true)
assert_contains "afk consumes injected run-state file" "SHFT_RUN_STATE_FILE" "$_afk_run_state_decl"
assert_contains "afk run-state fallback derives from lock" "_RUN_STATE_ID" "$_afk_run_state_decl"
assert_not_contains "afk run-state file is not global" 'shft-run.json' "$_afk_run_state_decl"

_afk_loop_block=$(sed -n '/^for i in /,/^done/p' shft/afk.sh)
assert_contains "afk checks lock between iterations" '[[ ! -d "$LOCKDIR" ]]' "$_afk_loop_block"

_afk_cleanup_fn=$(extract_function shft/afk.sh _cleanup_afk)
assert_contains "afk cleanup stops ticker" "_stop_ticker" "$_afk_cleanup_fn"
assert_contains "afk cleanup removes raw output" "raw_output" "$_afk_cleanup_fn"
_afk_exit_traps=$(grep -n "trap .*EXIT" shft/afk.sh || true)
assert_contains "afk has single cleanup exit trap" "_cleanup_afk" "$_afk_exit_traps"
_afk_exit_trap_count=$(printf '%s\n' "$_afk_exit_traps" | grep -c 'trap ' || true)
assert_eq "afk has exactly one EXIT trap" "1" "$_afk_exit_trap_count"

_afk_log_writes=$(grep -n '_log_afk' shft/afk.sh || true)
assert_contains "afk writes lifecycle log" "afk started" "$_afk_log_writes"

_build_prompt_text=$(cat shft/_build_prompt.sh)
assert_contains "prompt builder has worktree directive" "Isolated AFK Worktree Mode" "$_build_prompt_text"
assert_contains "prompt builder keeps one branch per run" "Later issues in this AFK run may depend" "$_build_prompt_text"

_help_block=$(sed -n '/^    help|--help|-h)/,/^        ;;$/p' shft/shft)
assert_contains "help documents worktree AFK" "shft afk --worktree" "$_help_block"
assert_contains "help documents worktrees command" "shft worktrees" "$_help_block"

_gitignore_runtime=$(grep -n 'working/runtime/afk-worktrees' .gitignore || true)
assert_contains "AFK worktrees are ignored" "working/runtime/afk-worktrees" "$_gitignore_runtime"

_run_with_secrets_syntax=$(grep -n 'expected KEY=value assignment' bin/run-with-secrets.sh || true)
assert_contains "run-with-secrets validates assignment syntax" "expected KEY=value assignment" "$_run_with_secrets_syntax"

echo
echo "run-with-secrets --only — filters injected credentials"
echo "────────────────────────────────────────────────"

_fake_home="$TMP/fake-home"
mkdir -p "$_fake_home/dotfiles/secrets"
cat > "$_fake_home/dotfiles/secrets/.env.secrets" <<'EOF'
GITHUB_APP_ID=dummy-app-id
GITHUB_APP_INSTALLATION_ID=12345
GITHUB_APP_PRIVATE_KEY_B64=dummy-private-key
GITHUB_TOKEN=dummy-pat
GITHUB_PACKAGE_REGISTRY_TOKEN=dummy-package-pat
EOF

_only_output=$(env -u GITHUB_TOKEN -u GITHUB_PACKAGE_REGISTRY_TOKEN HOME="$_fake_home" \
    bin/run-with-secrets.sh --only GITHUB_APP_ID,GITHUB_APP_INSTALLATION_ID,GITHUB_APP_PRIVATE_KEY_B64 -- \
    bash -c '[[ -n "${GITHUB_APP_ID:-}" ]] && [[ -n "${GITHUB_APP_INSTALLATION_ID:-}" ]] && [[ -n "${GITHUB_APP_PRIVATE_KEY_B64:-}" ]] && [[ -z "${GITHUB_TOKEN:-}" ]] && [[ -z "${GITHUB_PACKAGE_REGISTRY_TOKEN:-}" ]] && printf OK' \
    2>&1 || true)
assert_eq "--only injects App creds without PATs" "OK" "$_only_output"

_afk_validate_call=$(extract_function shft/shft _validate_afk)
assert_contains "shft AFK validation requests only App creds" "--only GITHUB_APP_ID,GITHUB_APP_INSTALLATION_ID,GITHUB_APP_PRIVATE_KEY_B64" "$_afk_validate_call"

_afk_app_secret_calls=$(grep -n 'GITHUB_APP_ID,GITHUB_APP_INSTALLATION_ID,GITHUB_APP_PRIVATE_KEY_B64' shft/afk.sh || true)
assert_contains "afk validation/mint requests only App creds" "GITHUB_APP_ID,GITHUB_APP_INSTALLATION_ID,GITHUB_APP_PRIVATE_KEY_B64" "$_afk_app_secret_calls"

_afk_env_decl=$(grep -n '_afk_env=(env' shft/afk.sh || true)
assert_contains "afk clears package PAT before Claude" "-u GITHUB_PACKAGE_REGISTRY_TOKEN" "$_afk_env_decl"

# ══════════════════════════════════════════════════════════════════════════════
# Summary
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
