#!/usr/bin/env bash
# copilot-drift.sh — Test that drift-detect covers copilot-instructions.md
#
# Run: bash test/copilot-drift.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$ROOT/working/tmp/copilot-drift-test"

PASS=0
FAIL=0
FAILURES=()

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

record_pass() { PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
record_fail() { FAIL=$((FAIL + 1)); FAILURES+=("$1 — $2"); printf '  \033[31m✗\033[0m %s — %s\n' "$1" "$2"; }

echo
echo "Copilot instruction drift tests"
echo "════════════════════════════════════════════════"

# ── Test: drift-detect.sh maps copilot-instructions.md to CLAUDE.md ───────────

if grep 'copilot-instructions.md' "$ROOT/bin/drift-detect.sh" | grep -q 'CLAUDE.md'; then
    record_pass "drift-detect.sh maps copilot-instructions.md to CLAUDE.md"
else
    record_fail "drift-detect.sh maps copilot-instructions.md to CLAUDE.md" "mapping not found"
fi

# ── Test: content drift is detected ──────────────────────────────────────────
# drift-detect.sh uses DOTFILES_ROOT (the repo) as source. CLAUDE.md is generated
# by bootstrap and won't exist in CI. We create it temporarily to test drift logic.

rm -rf "$TMP"
mkdir -p "$TMP/.copilot"

# Simulate generated CLAUDE.md in repo root
GENERATED_CLAUDE="$ROOT/CLAUDE.md"
CLEANUP_CLAUDE=false
if [[ ! -f "$GENERATED_CLAUDE" ]]; then
    echo "# Generated CLAUDE.md for testing" > "$GENERATED_CLAUDE"
    CLEANUP_CLAUDE=true
fi

# Create a diverged copilot-instructions.md (differs from repo CLAUDE.md)
echo "# Manually edited — this is NOT the real CLAUDE.md" > "$TMP/.copilot/copilot-instructions.md"

# Run drift-detect with our fake HOME
set +e
output=$(HOME="$TMP" bash "$ROOT/bin/drift-detect.sh" 2>&1)
status=$?
set -e

if [[ $status -ne 0 && "$output" == *"copilot-instructions.md"* ]]; then
    record_pass "content drift in copilot-instructions.md is reported"
else
    record_fail "content drift in copilot-instructions.md is reported" "exit=$status output: $output"
fi

# ── Test: --fix flag triggers bootstrap ───────────────────────────────────────

set +e
output=$(HOME="$TMP" bash "$ROOT/bin/drift-detect.sh" --fix 2>&1)
set -e

if [[ "$output" == *"bootstrap"* || "$output" == *"Bootstrap"* ]]; then
    record_pass "--fix mentions bootstrap repair"
else
    record_fail "--fix mentions bootstrap repair" "output: $output"
fi

# Clean up generated CLAUDE.md if we created it
if [[ "$CLEANUP_CLAUDE" == "true" ]]; then
    rm -f "$GENERATED_CLAUDE"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

printf "\n  \033[32m%d passed\033[0m  \033[31m%d failed\033[0m\n" "$PASS" "$FAIL"

if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo
    echo "Failures:"
    for f in "${FAILURES[@]}"; do printf '  \033[31m✗\033[0m %s\n' "$f"; done
    exit 1
fi
