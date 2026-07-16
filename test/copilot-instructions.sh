#!/usr/bin/env bash
# test/copilot-instructions.sh — Verify Copilot instructions are deployed from CLAUDE.md.
# Usage: bash test/copilot-instructions.sh
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
echo "Copilot instructions deployment"
echo "════════════════════════════════════════════════"

# ── bootstrap.sh deploys copilot-instructions.md ────────────────────────────
if grep -q 'copilot-instructions.md' bin/bootstrap.sh; then
    _ok "bootstrap.sh references copilot-instructions.md"
else
    _fail "bootstrap.sh references copilot-instructions.md" "not found in bootstrap.sh"
fi

# ── copilot-instructions.md target comes from CLAUDE.md (same source) ───────
if grep -q 'DOTFILES/CLAUDE.md.*COPILOT_DIR/copilot-instructions.md\|COPILOT_DIR/copilot-instructions.md.*DOTFILES/CLAUDE.md' bin/bootstrap.sh; then
    _ok "copilot-instructions.md is sourced from generated CLAUDE.md"
else
    # Check for ln -sf pointing CLAUDE.md -> copilot target
    if grep -q 'ln -sf "$DOTFILES/CLAUDE.md" "$COPILOT_DIR/copilot-instructions.md"' bin/bootstrap.sh; then
        _ok "copilot-instructions.md is sourced from generated CLAUDE.md"
    else
        _fail "copilot-instructions.md source" "not linked from CLAUDE.md"
    fi
fi

# ── validate-symlinks checks copilot-instructions.md ────────────────────────
if grep -q 'copilot-instructions.md' bin/validate-symlinks.sh; then
    _ok "validate-symlinks.sh checks copilot-instructions.md"
else
    _fail "validate-symlinks.sh checks copilot-instructions.md" "not found"
fi

# ── No root .github/copilot-instructions.md introduced ─────────────────────
if [[ -f ".github/copilot-instructions.md" ]]; then
    _fail "no root .github/copilot-instructions.md" "file exists but should not"
else
    _ok "no root .github/copilot-instructions.md"
fi

# ── Windows fallback (cp) is present ────────────────────────────────────────
if grep -q 'cp "$DOTFILES/CLAUDE.md" "$COPILOT_DIR/copilot-instructions.md"' bin/bootstrap.sh; then
    _ok "Windows copy fallback present for copilot-instructions.md"
else
    _fail "Windows copy fallback" "not found in bootstrap.sh"
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
