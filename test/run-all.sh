#!/usr/bin/env bash
# test/run-all.sh — Run all test suites in parallel, replay output sequentially.
#
# Replaces the sequential `npm run test:X && npm run test:Y && ...` chain.
# Each suite runs as a background job with stdout+stderr captured to a temp
# file. After all jobs complete, output is replayed suite-by-suite (no
# interleaving) and a summary reports which passed/failed.
#
# Usage:  bash test/run-all.sh
# Env:    SKIP_SLOW_TESTS=1  — skip hooks-integration + proxy-scripts (heavyweight suites)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Suite registry ──────────────────────────────────────────────────────────
# label:script pairs — order determines replay order.
SUITES=(
  "consistency:test/config-consistency.sh"
  "branch-guard:test/branch-write-guard.sh"
  "worktree-safety:test/worktree-safety.sh"
  "instructions:test/claude-instructions.sh"
  "skills:test/skills.sh"
  "copilot-skills:test/copilot-skills-materialize.sh"
  "hook-unit:test/hooks/run-hook-tests.sh"
  "hooks:test/hooks-integration.sh"
  "lifecycle:test/lifecycle.sh"
  "main-pr-source:test/main-pr-source-guard.sh"
  "verify-pr-base:test/verify-pr-base.sh"
  "pipeline-label:test/pipeline-label-wrapper.sh"
  "bridge-lifecycle:test/bridge-lifecycle.sh"
  "bridge-python:test/bridge-python.sh"
  "proxy-scripts:shft/templates/scripts/test_probe_completion.sh"
  "proxy-preflight:shft/templates/scripts/test_proxy_preflight.sh"
  "init-sandcastle-proxy-canary:test/init-sandcastle-proxy-canary.sh"
  "update-sandcastle-ownership:test/update-sandcastle-ownership.sh"
  "copilot-repo-local:test/copilot-repo-local-guard.sh"
  "mirror-regression:test/mirror-regression.sh"
  "smoke-coverage:test/sandcastle-smoke-coverage.sh"
)

# ── Temp dir for captured output ────────────────────────────────────────────
TMPDIR_RUN="$(mktemp -d 2>/dev/null || mktemp -d -t ctrlshft)"
trap 'rm -rf "$TMPDIR_RUN"' EXIT

# ── Launch all suites in parallel ───────────────────────────────────────────
declare -a PIDS=()
declare -a LABELS=()

for entry in "${SUITES[@]}"; do
  label="${entry%%:*}"
  script="${entry#*:}"

  # Allow skipping heavyweight suites in pre-commit
  if [[ "${SKIP_SLOW_TESTS:-}" == "1" && ( "$label" == "hooks" || "$label" == "proxy-scripts" ) ]]; then
    echo "⏭  Skipping $label (SKIP_SLOW_TESTS=1)"
    continue
  fi

  bash "$ROOT/$script" > "$TMPDIR_RUN/$label.out" 2>&1 &
  PIDS+=("$!")
  LABELS+=("$label")
done

# ── Wait for all jobs, collect exit codes ───────────────────────────────────
declare -a EXIT_CODES=()
for i in "${!PIDS[@]}"; do
  _ec=0
  wait "${PIDS[$i]}" 2>/dev/null || _ec=$?
  EXIT_CODES[$i]=$_ec
done

# ── Replay output sequentially ─────────────────────────────────────────────
# The ledger gate: a suite that exits 0 WITHOUT producing assertion evidence
# has silently checked nothing — the same false-green the saas-starter's
# assertWorkPerformed() invariant exists to prevent. Every suite must leave
# work evidence (✓/✗ markers, "passed"/"failed" counts, or "ok"/"not ok"
# lines) in its output before it may report success.
#
# A suite may opt out with a LEGACY_QUIET=1 env var (documented legacy suites
# with no assertion output), but the default is strict.
is_suite_quiet_legacy() {
  local label="$1"
  # Suites known to produce no assertion markers. Extend deliberately —
  # every addition here is a known gap, not an excuse.
  case "$label" in
    "") return 1 ;;
  esac
  return 1
}

suite_did_work() {
  local out_file="$1"
  # Work evidence = any assertion-like marker. Covers ✓/✗ unicode, ASCII
  # "[PASS]"/"[FAIL]"/"PASSED"/"FAILED", TAP "ok"/"not ok", and
  # pytest-style "passed"/"failed" counters.
  grep -qE $'✓|✗|\[PASS\]|\[FAIL\]|(PASSED|FAILED)|(^|[^[:alnum:]_])(ok|not ok)([^[:alnum:]_]|$)|passed|failed' "$out_file" 2>/dev/null
}

FAILED=0
LEDGER_VIOLATIONS=0
for i in "${!LABELS[@]}"; do
  label="${LABELS[$i]}"
  code="${EXIT_CODES[$i]}"
  out_file="$TMPDIR_RUN/$label.out"

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  if [[ "$code" -eq 0 ]]; then
    echo "  ✅  $label"
  else
    echo "  ❌  $label  (exit $code)"
    FAILED=$((FAILED + 1))
  fi
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  cat "$out_file"

  # Ledger gate: green suites must prove they did work.
  if [[ "$code" -eq 0 ]] && ! is_suite_quiet_legacy "$label" && ! suite_did_work "$out_file"; then
    echo "  ⚠️  LEDGER VIOLATION: $label exited 0 but produced no assertion evidence."
    echo "     A green run that checks nothing is not green. Add assertion output or"
    echo "     register it as a quiet-legacy suite in run-all.sh."
    LEDGER_VIOLATIONS=$((LEDGER_VIOLATIONS + 1))
  fi
done

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════════════"
TOTAL="${#LABELS[@]}"
PASSED=$((TOTAL - FAILED))
echo "  $PASSED/$TOTAL suites passed"
if [[ "$FAILED" -gt 0 ]]; then
  echo ""
  for i in "${!LABELS[@]}"; do
    [[ "${EXIT_CODES[$i]}" -ne 0 ]] && echo "  FAIL: ${LABELS[$i]} (exit ${EXIT_CODES[$i]})"
  done
  echo "════════════════════════════════════════════════════════════════════"
  exit 1
fi
if [[ "$LEDGER_VIOLATIONS" -gt 0 ]]; then
  echo "  $LEDGER_VIOLATIONS ledger violation(s) — green suites that did no work"
  echo "════════════════════════════════════════════════════════════════════"
  exit 1
fi
echo "════════════════════════════════════════════════════════════════════"
exit 0
