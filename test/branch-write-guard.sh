#!/usr/bin/env bash
# test/branch-write-guard.sh — Fail loud if the "no AI writes to main" guards regress.
#
# The incident this defends against: an AI agent merged a promotion PR to main
# and then force-reset main — both with zero friction. These invariants make
# that impossible to reintroduce SILENTLY:
#   1. the git-native pre-push hook still refuses pushes to main/master on the
#      private origin — this is the layer that covers EVERY local tool, including
#      agents whose Claude Code PreToolUse hooks never fire (e.g. the VS Code
#      Copilot agent);
#   2. that guard actually behaves (blocks main, allows feature branches, honors
#      the human break-glass);
#   3. the server-side ruleset backstop is DEFINED in-repo and appliable.
#
# Live application of the ruleset on GitHub is reported (a human applies it
# out-of-band via bin/apply-branch-ruleset.sh), but its absence NEVER fails the
# build — offline/CI runs skip the gh check so the pre-commit/CI gate stays green.
#
# Usage: bash test/branch-write-guard.sh   (exit 0 = all invariants hold)

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT"

PASS=0; FAIL=0; SKIP=0
FAILURES=()
ok()   { PASS=$((PASS + 1)); printf "  \033[32m✓\033[0m %s\n" "$1"; }
bad()  { FAIL=$((FAIL + 1)); FAILURES+=("$1"); printf "  \033[31m✗\033[0m %s\n" "$1"; }
skip() { SKIP=$((SKIP + 1)); printf "  \033[33m~\033[0m %s\n" "$1"; }

PRIV="https://github.com/arndvs/dotfiles-private.git"
HOOK="$ROOT/git-hooks/pre-push"

# Run the pre-push hook with a remote URL + a "<local> <lsha> <remote> <rsha>"
# ref line on stdin; echo its exit code (0 = allowed, non-zero = blocked).
_prepush() {
    printf '%s\n' "$2" | DOTFILES="$ROOT" bash "$HOOK" origin "$1" >/dev/null 2>&1
    echo $?
}

echo "── no-AI-writes-to-main guards ──"

# ── Invariant 1 — the pre-push guard is present in source ────────────────────
if grep -q 'is_private_ctrlshft_remote_url' "$HOOK" && grep -q 'refs/heads/main' "$HOOK"; then
    ok "pre-push hook contains the production-branch guard"
else
    bad "pre-push hook is MISSING the production-branch guard (was it removed?)"
fi

# ── Invariant 2 — it blocks pushes to main/master on the private origin ──────
if [ "$(_prepush "$PRIV" 'refs/heads/dev a refs/heads/main b')" -ne 0 ]; then
    ok "pre-push blocks push to main on the private origin"
else
    bad "pre-push ALLOWED a push to main on the private origin"
fi
if [ "$(_prepush "$PRIV" 'refs/heads/dev a refs/heads/master b')" -ne 0 ]; then
    ok "pre-push blocks push to master on the private origin"
else
    bad "pre-push ALLOWED a push to master on the private origin"
fi

# ── Invariant 3 — it does NOT block the sanctioned feature-branch flow ───────
if [ "$(_prepush "$PRIV" 'refs/heads/ai/x a refs/heads/ai/x b')" -eq 0 ]; then
    ok "pre-push allows feature-branch pushes (sanctioned flow intact)"
else
    bad "pre-push wrongly blocked a feature-branch push"
fi

# ── Invariant 4 — human break-glass works ───────────────────────────────────
_bg=$(printf 'refs/heads/dev a refs/heads/main b\n' \
    | CTRL_ALLOW_MAIN_PUSH=1 DOTFILES="$ROOT" bash "$HOOK" origin "$PRIV" >/dev/null 2>&1; echo $?)
if [ "$_bg" -eq 0 ]; then
    ok "CTRL_ALLOW_MAIN_PUSH=1 break-glass permits the push"
else
    bad "break-glass CTRL_ALLOW_MAIN_PUSH=1 did not permit the push"
fi

# ── Invariant 5 — the server-side ruleset backstop is defined in-repo ────────
if [ -f ".github/rulesets/main.json" ] \
    && grep -q '"non_fast_forward"' .github/rulesets/main.json \
    && grep -q '"pull_request"' .github/rulesets/main.json; then
    ok "server ruleset IaC present (.github/rulesets/main.json: PR + no-force-push)"
else
    bad "server ruleset IaC missing/incomplete (.github/rulesets/main.json)"
fi
if [ -f "bin/apply-branch-ruleset.sh" ]; then
    ok "bin/apply-branch-ruleset.sh present"
else
    bad "bin/apply-branch-ruleset.sh missing"
fi

# ── Informational — is the ruleset actually applied on GitHub? ───────────────
# A human applies this out-of-band; its ABSENCE must not fail CI/offline runs.
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    _rs_json=$(gh api repos/arndvs/dotfiles-private/rulesets 2>/dev/null || true)
    if printf '%s' "$_rs_json" | grep -q 'Upgrade to GitHub Pro\|"status": *"403"'; then
        skip "rulesets unavailable on this plan (private repo needs GitHub Pro) — local guard is primary"
    else
        _rs=$(printf '%s' "$_rs_json" | jq '[.[]? | select(.target=="branch")] | length' 2>/dev/null || echo err)
        if [ "$_rs" = "err" ]; then
            skip "could not query rulesets (permission/network) — live check skipped"
        elif [ "$_rs" -gt 0 ] 2>/dev/null; then
            ok "a branch ruleset is applied on GitHub ($_rs active)"
        else
            skip "no branch ruleset applied yet — run: bin/apply-branch-ruleset.sh"
        fi
    fi
else
    skip "gh not authenticated — live ruleset check skipped (offline/CI)"
fi

echo ""
echo "  Results: $PASS passed, $FAIL failed, $SKIP skipped"
if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "A no-AI-writes-to-main guard regressed — fix before shipping:"
    printf '  - %s\n' "${FAILURES[@]}"
    exit 1
fi
exit 0
