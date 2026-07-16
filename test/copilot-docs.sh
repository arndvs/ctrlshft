#!/usr/bin/env bash
# test/copilot-docs.sh — Verify documentation covers the mirrored Claude/Copilot instruction model.
# Usage: bash test/copilot-docs.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$(dirname "$0")/..")"

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

echo
echo "Copilot mirrored-instructions documentation"
echo "════════════════════════════════════════════════"

# ── Architecture docs state Copilot mirrors Claude instructions ─────────────
if grep -qi 'copilot.*mirror\|mirror.*copilot\|mirrored' docs/ARCHITECTURE.md; then
    _ok "ARCHITECTURE.md documents mirrored Copilot instructions"
else
    _fail "ARCHITECTURE.md documents mirrored instructions" "no mirror reference found"
fi

# ── Docs warn not to edit copilot-instructions.md directly ──────────────────
if grep -qi 'never edit.*copilot-instructions\|do not edit.*copilot-instructions' docs/ARCHITECTURE.md README.md; then
    _ok "Docs warn against editing copilot-instructions.md directly"
else
    _fail "Docs warn against direct edit" "no warning found in ARCHITECTURE.md or README.md"
fi

# ── Bootstrap/validation/drift docs mention Copilot target ──────────────────
if grep -q 'validate-symlinks.*copilot\|drift-detect.*copilot\|copilot.*validate\|copilot.*drift' docs/ARCHITECTURE.md README.md; then
    _ok "Docs mention validation/drift-detection for Copilot target"
else
    _fail "Validation docs mention Copilot" "not found in ARCHITECTURE.md or README.md"
fi

# ── Changelog records mirrored instruction deployment ───────────────────────
if grep -qi 'copilot.*instruction\|mirrored.*instruction\|instruction.*copilot' CHANGELOG.md; then
    _ok "CHANGELOG records mirrored instruction deployment"
else
    _fail "CHANGELOG entry" "no mirrored instruction entry found"
fi

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
