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

echo ""
printf "  %d passed  %d failed\n" "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
