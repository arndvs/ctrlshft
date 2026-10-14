#!/usr/bin/env bash
# hud-afk-paths.sh — AFK HUD events must use the canonical emitter and the
# daemon's logs path (#323). Hermetic: no daemon, no pipe, no network.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf "  ✓ %s\n" "$1"; }
fail() { FAIL=$((FAIL + 1)); printf "  ✗ %s\n" "$1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "── hud afk paths (#323) ──"

# Static: the dead JSONL path must not be written by the AFK emitter.
if grep -q 'WORKING_DIR/events.jsonl' "$ROOT/shft/afk.sh"; then
  fail "afk.sh still writes working/events.jsonl (dead path)"
else
  pass "afk.sh does not write working/events.jsonl"
fi

# Static: the AFK emitter delegates to the canonical writer.
if grep -qE '^[[:space:]]*(source|\.)[[:space:]].*write-hud-state\.sh' "$ROOT/shft/afk.sh"; then
  pass "afk.sh sources canonical write-hud-state.sh"
else
  fail "afk.sh does not source canonical write-hud-state.sh"
fi

# Behavioural: with no pipe or daemon, an AFK-tagged event lands in
# DOTFILES/working/logs/events.jsonl (the file the daemon polls), with source.
out=$(DOTFILES="$TMP/dot" HUD_PORT=1 bash -c 'set -euo pipefail; source "$1"; write_hud_event "info" "AFK iteration 1 of 3 started" "" "" "afk"' _ "$ROOT/bin/write-hud-state.sh" 2>&1) || true
LOG="$TMP/dot/working/logs/events.jsonl"
if [[ -f "$LOG" ]] && grep -q '"source":"afk"' "$LOG" && grep -q 'AFK iteration 1 of 3 started' "$LOG"; then
  pass "afk event lands in working/logs/events.jsonl with source=afk"
else
  fail "afk event missing from working/logs/events.jsonl (output: $out)"
fi

# Behavioural: nothing written to the dead working/events.jsonl location.
if [[ ! -f "$TMP/dot/working/events.jsonl" ]]; then
  pass "no event written to working/events.jsonl"
else
  fail "event written to dead working/events.jsonl"
fi

# Behavioural: untagged events keep the original payload shape (no source key).
DOTFILES="$TMP/plain" HUD_PORT=1 bash -c 'source "$1"; write_hud_event "info" "plain"' _ "$ROOT/bin/write-hud-state.sh" >/dev/null 2>&1 || true
if grep -q '"source"' "$TMP/plain/working/logs/events.jsonl" 2>/dev/null; then
  fail "untagged event unexpectedly carries a source key"
else
  pass "untagged event payload unchanged (no source key)"
fi

# ── #323 part 2: once.sh emits, detect-context collapses to canonical emitter ──

# Static: once.sh sources the canonical writer and emits start/finish events.
if grep -qE '^[[:space:]]*source[[:space:]].*write-hud-state\.sh' "$ROOT/shft/once.sh" \
   && grep -q 'write_hud_event' "$ROOT/shft/once.sh"; then
  pass "once.sh sources canonical writer and emits HUD events"
else
  fail "once.sh does not emit HUD events"
fi

# Static: detect-context.sh no longer hand-builds a payload or writes the pipe itself.
if grep -q '_dc_payload=' "$ROOT/bin/detect-context.sh" || grep -q '_dc_pipe=' "$ROOT/bin/detect-context.sh"; then
  fail "detect-context.sh still hand-rolls the HUD emitter"
else
  pass "detect-context.sh has no inline HUD emitter"
fi

# Static: detect-context.sh routes through the canonical context event.
if grep -q 'write_hud_event "context"' "$ROOT/bin/detect-context.sh"; then
  pass "detect-context.sh emits context via write_hud_event"
else
  fail "detect-context.sh does not emit via write_hud_event"
fi

# Behavioural: running detect-context in a project dir with no daemon writes a
# context event with the ide field into DOTFILES/working/logs/events.jsonl.
PROJ="$TMP/proj"
mkdir -p "$PROJ"
echo '{"name":"x","dependencies":{"expo":"1"}}' > "$PROJ/package.json"
(cd "$PROJ" && env -u VSCODE_PID -u VSCODE_IPC_HOOK -u CURSOR_SESSION_ID \
  DOTFILES="$TMP/ctx" HUD_PORT=1 bash "$ROOT/bin/detect-context.sh" >/dev/null 2>&1) || true
CTX_LOG="$TMP/ctx/working/logs/events.jsonl"
# Emission is backgrounded (cd must not block), so poll briefly for the write.
for _ in $(seq 1 20); do
  [[ -s "$CTX_LOG" ]] && break
  sleep 0.2
done
if [[ -f "$CTX_LOG" ]] && grep -q '"type":"context"' "$CTX_LOG" \
   && grep -q '"ide":"terminal"' "$CTX_LOG" && grep -q 'Active contexts: .*expo' "$CTX_LOG"; then
  pass "context event lands in logs with ide field and contexts"
else
  fail "context event missing or malformed in $CTX_LOG"
fi

echo ""
printf "  %d passed  %d failed\n" "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
