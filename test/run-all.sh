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
  "instructions:test/claude-instructions.sh"
  "hooks:test/hooks-integration.sh"
  "lifecycle:test/lifecycle.sh"
  "main-pr-source:test/main-pr-source-guard.sh"
  "pipeline-label:test/pipeline-label-wrapper.sh"
  "bridge-python:test/bridge-python.sh"
  "proxy-scripts:shft/templates/scripts/test_probe_completion.sh"
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
FAILED=0
for i in "${!LABELS[@]}"; do
  label="${LABELS[$i]}"
  code="${EXIT_CODES[$i]}"

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  if [[ "$code" -eq 0 ]]; then
    echo "  ✅  $label"
  else
    echo "  ❌  $label  (exit $code)"
    FAILED=$((FAILED + 1))
  fi
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  cat "$TMPDIR_RUN/$label.out"
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
echo "════════════════════════════════════════════════════════════════════"
exit 0
