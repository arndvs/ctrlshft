#!/usr/bin/env bash
# test/worktree-safety.sh — Verify the worktree prune safety model invariants.
#
# The value of ctrl-worktree.sh is its safety model, ported from saas-starter's
# prune-worktrees.ts:
#   1. '[gone]' upstream alone never deletes a branch. Deletion requires a
#      confirmed merge (git ancestry OR SHA-matched merged PR).
#   2. A '[gone]' branch whose content is NOT in trunk is kept (classified
#      not-merged/unknown), never deleted.
#   3. The currently checked-out branch and trunk are never candidates.
#   4. --dry-run changes nothing.
#
# Usage: bash test/worktree-safety.sh   (exit 0 = all invariants hold)

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
WORKTREE_BIN="$ROOT/bin/ctrl-worktree.sh"

PASS=0; FAIL=0
FAILURES=()
ok()   { PASS=$((PASS + 1)); printf "  \033[32m✓\033[0m %s\n" "$1"; }
bad()  { FAIL=$((FAIL + 1)); FAILURES+=("$1"); printf "  \033[31m✗\033[0m %s\n" "$1"; }

# ── Isolated test repo ───────────────────────────────────────────────────────
TMP_BASE="$(mktemp -d 2>/dev/null || mktemp -d -t ctrlshft-worktree)"
trap 'rm -rf "$TMP_BASE"' EXIT

BARE="$TMP_BASE/bare.git"
CLONE="$TMP_BASE/clone"
mkdir -p "$BARE"
git init -q --bare "$BARE"

git clone -q "$BARE" "$CLONE" 2>/dev/null
cd "$CLONE"
git config user.email "test@ctrlshft.test"
git config user.name "CtrlShft Test"
echo "init" > f.txt
git add .
git commit -qm "init"
git branch -M main
git push -q origin main

# ── Fixture: a branch that merged into main, remote branch deleted ─────────
git checkout -qb feat/merged
echo "merged work" >> f.txt
git commit -qam "merged work"
git push -q origin feat/merged
git checkout -q main
git merge -q --ff-only feat/merged
git push -q origin main

# ── Fixture: a [gone] branch whose content is NOT in main (unmerged) ──────
git checkout -q -b feat/unmerged-gone
echo "unmerged work" >> f.txt
git commit -qam "unmerged work"
git push -q origin feat/unmerged-gone
git checkout -q main

# Set upstream tracking BEFORE culling the remote branches, so git records the
# upstream and the cull transforms it into [gone]. Ensure remote refs exist
# locally first so --set-upstream-to can resolve them.
git fetch -q origin
git branch --set-upstream-to=origin/feat/merged feat/merged
git branch --set-upstream-to=origin/feat/unmerged-gone feat/unmerged-gone

echo "  Culling remote branches to simulate merged-PR deletion..."
(cd "$BARE" && git update-ref -d refs/heads/feat/merged && git update-ref -d refs/heads/feat/unmerged-gone)

echo ""
echo "Worktree prune safety model"
echo "════════════════════════════"
echo ""

# ── Test 1: dry-run identifies the merged branch as deletable ─────────────
DRY_RUN_OUTPUT="$(CTRL_WORKTREE_NO_FETCH=1 bash "$WORKTREE_BIN" prune --dry-run 2>&1 || true)"
if printf '%s\n' "$DRY_RUN_OUTPUT" | grep -q "would delete branch feat/merged"; then
    ok "dry-run flags confirmed-merged [gone] branch for deletion"
else
    bad "dry-run did not flag merged [gone] branch — output: $DRY_RUN_OUTPUT"
fi

# ── Test 2: the unmerged [gone] branch is NEVER deleted ────────────────────
if printf '%s\n' "$DRY_RUN_OUTPUT" | grep -q "would delete branch feat/unmerged-gone"; then
    bad "safety violation: unmerged [gone] branch scheduled for deletion"
else
    ok "unmerged [gone] branch is kept (cannot confirm merge)"
fi

# ── Test 3: dry-run changes nothing ────────────────────────────────────────
BRANCHES_BEFORE="$(git branch --format='%(refname:short)' | sort | tr '\n' ' ')"
CTRL_WORKTREE_NO_FETCH=1 bash "$WORKTREE_BIN" prune --dry-run >/dev/null 2>&1 || true
BRANCHES_AFTER="$(git branch --format='%(refname:short)' | sort | tr '\n' ' ')"
if [[ "$BRANCHES_BEFORE" == "$BRANCHES_AFTER" ]]; then
    ok "dry-run leaves all branches untouched"
else
    bad "dry-run modified branches: before='$BRANCHES_BEFORE' after='$BRANCHES_AFTER'"
fi

# ── Test 4: the current branch is never a candidate ────────────────────────
git checkout -q feat/merged
CURRENT_OUT="$(CTRL_WORKTREE_NO_FETCH=1 bash "$WORKTREE_BIN" prune --dry-run 2>&1 || true)"
if printf '%s\n' "$CURRENT_OUT" | grep -qE "would (delete|remove).*feat/merged|feat/merged.*would (delete|remove)"; then
    bad "current checked-out branch was scheduled for deletion"
else
    ok "currently checked-out branch is never a prune candidate"
fi

echo ""
echo "══════════════════════════════════════════════════════"
echo "  $PASS passed, $FAIL failed"
echo "══════════════════════════════════════════════════════"

if [[ "$FAIL" -gt 0 ]]; then
    for failure in "${FAILURES[@]}"; do
        echo "  ✗ $failure"
    done
    exit 1
fi
exit 0