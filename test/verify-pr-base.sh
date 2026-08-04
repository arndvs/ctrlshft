#!/usr/bin/env bash
# test/verify-pr-base.sh — Verify bin/verify-pr-base.sh resolves the base
# authoritatively and catches wrong-base merges.
#
# Covers:
#   1. sandcastle.config.json baseBranch fallback (no PR, no gh)
#   2. Fail-loud when base is undeterminable (no config, no gh)
#   3. Ancestry check passes for a clean dev-based branch
#   4. Ancestry check fails for a main-based branch that merged dev in
#   5. Pre-push hook contains the wrong-base-merge guard
#
# The ancestry cases build synthetic git repos in a temp dir so they are
# deterministic and offline (no gh, no network).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$ROOT/bin/verify-pr-base.sh"
HOOK="$ROOT/git-hooks/pre-push"

PASS=0
FAIL=0
FAILURES=()

record_pass() {
    PASS=$((PASS + 1))
    printf "  \033[32m✓\033[0m %s\n" "$1"
}

record_fail() {
    FAIL=$((FAIL + 1))
    FAILURES+=("$1 — $2")
    printf "  \033[31m✗\033[0m %s — %s\n" "$1" "$2"
}

# ── Test 1: guard script exists and is executable ───────────────────────────
if [[ -x "$GUARD" ]]; then
    record_pass "verify-pr-base.sh exists and is executable"
else
    record_fail "verify-pr-base.sh exists and is executable" "$GUARD missing or not executable"
fi

# ── Test 2: sandcastle.config.json baseBranch fallback ──────────────────────
# Run in a temp dir with a sandcastle.config.json but no gh on PATH, so the
# resolver must fall back to the config's baseBranch.
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t verifyprbase)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin"
cp "$GUARD" "$TMP/bin/verify-pr-base.sh"
printf '{"baseBranch":"dev"}\n' > "$TMP/sandcastle.config.json"

# Simulate a git repo with a current branch (no gh available).
(
    cd "$TMP"
    git init -q
    git checkout -q -b ai/fix/example 2>/dev/null || git checkout -q -b ai/fix/example
)

# Hide gh so the resolver cannot use it, but keep jq (needed for the config
# fallback). Build a PATH that excludes gh's directory.
_gh_dir="$(dirname "$(command -v gh 2>/dev/null || echo /nonexistent)")"
_restricted_path="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v "^$_gh_dir$" | paste -sd: -)"
_resolved=$(cd "$TMP" && PATH="$_restricted_path" bash bin/verify-pr-base.sh 2>/dev/null || true)
if [[ "$_resolved" == "dev" ]]; then
    record_pass "falls back to sandcastle.config.json baseBranch (dev)"
else
    record_fail "falls back to sandcastle.config.json baseBranch" "got '$_resolved', expected 'dev'"
fi

# ── Test 3: fail loud when base is undeterminable ────────────────────────────
# No sandcastle.config.json, no gh → must exit 1, never guess.
TMP2="$(mktemp -d 2>/dev/null || mktemp -d -t verifyprbase2)"
trap 'rm -rf "$TMP" "$TMP2"' EXIT
mkdir -p "$TMP2/bin"
cp "$GUARD" "$TMP2/bin/verify-pr-base.sh"
(
    cd "$TMP2"
    git init -q
    git checkout -q -b ai/fix/example 2>/dev/null || git checkout -q -b ai/fix/example
)
set +e
(cd "$TMP2" && PATH="$_restricted_path" bash bin/verify-pr-base.sh >/dev/null 2>&1)
_status=$?
set -e
if [[ "$_status" -ne 0 ]]; then
    record_pass "fails loud (exit 1) when base is undeterminable"
else
    record_fail "fails loud when base is undeterminable" "exited 0 (guessed a base)"
fi

# ── Test 4: ancestry check passes for a clean dev-based branch ───────────────
# Build: main → dev → feature. Feature is based on dev, so no foreign commits.
TMP3="$(mktemp -d 2>/dev/null || mktemp -d -t verifyprbase3)"
trap 'rm -rf "$TMP" "$TMP2" "$TMP3"' EXIT
mkdir -p "$TMP3/bin"
cp "$GUARD" "$TMP3/bin/verify-pr-base.sh"
(
    cd "$TMP3"
    git init -q
    git config user.email test@example.com
    git config user.name test
    git checkout -q -b main
    echo main > f.txt && git add f.txt && git commit -qm "main"
    git checkout -q -b dev
    echo dev > f.txt && git add f.txt && git commit -qm "dev"
    git checkout -q -b feature
    echo feature > f.txt && git add f.txt && git commit -qm "feature"
    # Simulate origin refs
    git update-ref refs/remotes/origin/main main
    git update-ref refs/remotes/origin/dev dev
)
# Feature is based on dev; base resolves to dev (config absent → but we pass
# --branch and rely on ancestry only; base resolution needs config/gh, so pass
# --branch and let it fall to default. To make it deterministic, write a config.
printf '{"baseBranch":"dev"}\n' > "$TMP3/sandcastle.config.json"
set +e
(cd "$TMP3" && PATH="$_restricted_path" bash bin/verify-pr-base.sh --branch feature --check-ancestry --quiet >/dev/null 2>&1)
_status=$?
set -e
if [[ "$_status" -eq 0 ]]; then
    record_pass "ancestry check passes for clean dev-based branch"
else
    record_fail "ancestry check passes for clean dev-based branch" "exited $_status"
fi

# ── Test 5: ancestry check fails for a main-based branch that merged dev ─────
# Build: main → dev → feature, then merge dev into feature (wrong base).
TMP4="$(mktemp -d 2>/dev/null || mktemp -d -t verifyprbase4)"
trap 'rm -rf "$TMP" "$TMP2" "$TMP3" "$TMP4"' EXIT
mkdir -p "$TMP4/bin"
cp "$GUARD" "$TMP4/bin/verify-pr-base.sh"
(
    cd "$TMP4"
    git init -q
    git config user.email test@example.com
    git config user.name test
    git checkout -q -b main
    echo main > f.txt && git add f.txt && git commit -qm "main"
    git checkout -q -b dev
    echo dev > f.txt && git add f.txt && git commit -qm "dev"
    git checkout -q -b feature
    echo feature > f.txt && git add f.txt && git commit -qm "feature"
    # Wrong-base merge: bring dev's commit into feature (as if base were dev)
    git merge -q --no-edit dev 2>/dev/null || true
    git update-ref refs/remotes/origin/main main
    git update-ref refs/remotes/origin/dev dev
)
printf '{"baseBranch":"main"}\n' > "$TMP4/sandcastle.config.json"
set +e
(cd "$TMP4" && PATH="$_restricted_path" bash bin/verify-pr-base.sh --branch feature --check-ancestry --quiet >/dev/null 2>&1)
_status=$?
set -e
if [[ "$_status" -ne 0 ]]; then
    record_pass "ancestry check fails for main-based branch that merged dev"
else
    record_fail "ancestry check fails for main-based branch that merged dev" "exited 0 (missed wrong-base merge)"
fi

# ── Test 6: pre-push hook contains the wrong-base-merge guard ────────────────
if [[ -f "$HOOK" ]] && grep -q 'verify-pr-base.sh' "$HOOK" && grep -q -- '--check-ancestry' "$HOOK"; then
    record_pass "pre-push hook contains the wrong-base-merge guard"
else
    record_fail "pre-push hook contains the wrong-base-merge guard" "$HOOK missing verify-pr-base ancestry check"
fi

echo
echo "verify-pr-base guard tests"
echo "══════════════════════════"
printf "  \033[32m%d passed\033[0m  \033[31m%d failed\033[0m\n" "$PASS" "$FAIL"

if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo
    echo "  Failures:"
    for f in "${FAILURES[@]}"; do
        printf "    \033[31m✗\033[0m %s\n" "$f"
    done
    exit 1
fi
exit 0
