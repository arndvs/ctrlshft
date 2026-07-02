#!/usr/bin/env bash
# test/config-consistency.sh — Fail loud on silent config drift.
#
# The auto-Copilot-review hook silently stopped firing because the DEPLOYED
# Claude settings source (.claude/settings.json) dropped a hook that the
# reference (hooks/settings-hooks.json) still listed. Nothing failed — the
# behavior just quietly disappeared until a human noticed the symptom.
#
# This suite converts that whole class of "source-of-truth drift" into a red,
# blocking check. These are REPO-INTERNAL invariants (both files live in git),
# so they run in CI and the pre-commit gate — a failing build instead of a
# capability that silently degrades. Deploy-side drift (~/.claude vs repo) is a
# separate, local concern covered by bin/drift-detect.sh.
#
# Add an invariant whenever you find a "this should always be true but nothing
# checks it" gap. Cheap to run (JSON parse + file existence), so it stays in the
# default `npm test` chain.
#
# Usage: bash test/config-consistency.sh   (exit 0 = all invariants hold)

set -euo pipefail

# Hermetic git env — never let hook-exported GIT_* leak into this suite.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR \
      GIT_OBJECT_DIRECTORY GIT_NAMESPACE 2>/dev/null || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v jq >/dev/null 2>&1; then
    echo "config-consistency: jq is required" >&2
    exit 1
fi

PASS=0
FAIL=0
FAILURES=()
green() { printf "  \033[32m✓\033[0m %s\n" "$1"; }
red()   { printf "  \033[31m✗\033[0m %s\n" "$1"; }
ok()  { PASS=$((PASS + 1)); green "$1"; }
bad() { FAIL=$((FAIL + 1)); FAILURES+=("$1"); red "$1"; }

# Set of hook script basenames referenced anywhere in a settings JSON's hooks
# tree (any event, any matcher; ignores non-hook keys like permissions/theme,
# and unwraps `bash -c '... script.py ...'` since we match the basename).
# `(.hooks // {})` treats a missing hooks block as an empty set instead of a jq
# error; `.command // empty` skips entries without a command. jq parse errors on
# malformed JSON are deliberately NOT silenced (a broken settings file should
# surface loudly). grep is made non-fatal so "this file has no hooks" yields an
# empty set rather than a pipefail abort of the whole suite under `set -e`.
hook_set() {
    jq -r '(.hooks // {}) | to_entries[] | .value[]? | .hooks[]? | .command // empty' "$1" \
        | { grep -oE '[A-Za-z0-9_-]+\.(sh|py)' || true; } | sort -u
}

echo "── config drift guards ──"

# ── Invariant 1 — the regression that started this ───────────────────────────
# The deployed settings (.claude/settings.json, what bootstrap installs) and the
# hooks reference (hooks/settings-hooks.json, what drift-detect compares) must
# list the SAME hooks. Dropping a hook from either — as happened with
# gh-pr-auto-copilot-review.sh — fails here at commit/PR time, not months later.
_deployed=$(hook_set .claude/settings.json)
_reference=$(hook_set hooks/settings-hooks.json)
if [ "$_deployed" = "$_reference" ]; then
    ok "Claude hook set matches: .claude/settings.json == hooks/settings-hooks.json"
else
    bad "Claude hook set DRIFT between .claude/settings.json and hooks/settings-hooks.json"
    echo "    only in .claude/settings.json:"
    comm -23 <(printf '%s\n' "$_deployed") <(printf '%s\n' "$_reference") | sed 's/^/      /'
    echo "    only in hooks/settings-hooks.json:"
    comm -13 <(printf '%s\n' "$_deployed") <(printf '%s\n' "$_reference") | sed 's/^/      /'
fi

# ── Invariant 2 — no dangling hook references ────────────────────────────────
# Every hook the settings invoke must exist as a file, or Claude Code silently
# skips a hook that was renamed/deleted out from under the config.
_missing=0
for h in $_deployed; do
    [ -f "hooks/$h" ] || { bad "settings reference a missing hook file: hooks/$h"; _missing=1; }
done
[ "$_missing" -eq 0 ] && ok "every hook referenced by settings exists in hooks/"

# ── Invariant 3 — sourced library is present ─────────────────────────────────
# Hooks that `source _hooklib.sh` are fail-closed; if the library is missing the
# source fails and they DENY everything. Guarantee the library ships with them.
if grep -lE '^[[:space:]]*(source|\.)[[:space:]]+[^#]*_hooklib\.sh' hooks/*.sh >/dev/null 2>&1; then
    if [ -f hooks/_hooklib.sh ]; then
        ok "_hooklib.sh present for the hooks that source it"
    else
        bad "hooks source _hooklib.sh but hooks/_hooklib.sh is MISSING (fail-closed hooks would deny)"
    fi
fi

# ── Invariant 4 — the auto-review guarantee is wired repo-side ───────────────
# The Claude hook only covers PRs opened under Claude Code; this workflow is the
# deterministic guarantee for every other PR (Sandcastle Actions, VS Code, etc).
# Assert it exists and actually requests Copilot on pull_request events.
_wf=".github/workflows/pr-auto-copilot-review.yml"
if [ -f "$_wf" ] \
    && grep -q "copilot-pull-request-reviewer" "$_wf" \
    && grep -qE '^[[:space:]]*pull_request:' "$_wf"; then
    ok "pr-auto-copilot-review.yml requests Copilot on pull_request"
else
    bad "pr-auto-copilot-review.yml missing/incomplete — repo-side auto-review guarantee not enforced"
fi

echo ""
echo "  Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "Drift found — fix the source files above so the invariant holds again."
    printf '  - %s\n' "${FAILURES[@]}"
    exit 1
fi
exit 0
