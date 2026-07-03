#!/usr/bin/env bash
# test/lifecycle.sh — Integration tests for the artifact lifecycle commands:
#   init-artifacts, update-artifacts, artifact-lifecycle-audit
# plus repo-local working/active plan discovery and ignore-lane correctness.
# See docs/ARTIFACT-LIFECYCLE.md for the lifecycle specification.
#
# Usage: bash test/lifecycle.sh
# Exit: 0 if all pass, 1 if any fail.
#
# PARALLEL GROUP PATTERN
# ──────────────────────
# Tests are organized into _group_<name>() functions registered in _GROUPS.
# Each group runs in a background subshell. Groups MUST NOT share mutable
# state — each creates its own temp directories and git repos. Results are
# written to per-group files and aggregated after `wait`.
#
# Current groups:
#   _group_init   — init-artifacts, ignore/tracked lanes, plan discovery
#   _group_update — update-artifacts tests
#   _group_audit  — artifact-lifecycle-audit tests
#
# To add a group: define _group_yourname(), add "_group_yourname" to _GROUPS.
set -uo pipefail

# When invoked from the pre-commit hook, git exports GIT_DIR / GIT_INDEX_FILE /
# GIT_WORK_TREE et al. into the environment. Left set, they would hijack the git
# commands this test runs inside throwaway temp repos onto the parent repo (e.g.
# `git init` reinitializing the real .git, `git add` staging parent files).
# Unset them so every temp-repo git invocation is fully isolated, whether this
# script runs standalone or as part of `npm test` under the commit hook.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR \
      GIT_OBJECT_DIRECTORY GIT_NAMESPACE 2>/dev/null || true

# Resolve the repo root from this script's own location (matches the pattern in
# hooks-integration.sh) so `npm test` works from any checkout path, not just
# ~/dotfiles (e.g. CI workspaces). An explicit DOTFILES env override still wins.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES="${DOTFILES:-$REPO_ROOT}"
INIT="$DOTFILES/bin/init-artifacts.sh"
UPDATE="$DOTFILES/bin/update-artifacts.sh"
AUDIT="$DOTFILES/bin/artifact-lifecycle-audit.sh"
PLAN_GATE="$DOTFILES/hooks/plan-quality-gate.sh"

PASS=0
FAIL=0
FAILURES=()

# ── Cleanup trap ──────────────────────────────────────────────────────────────
_CLEANUP_DIRS=()
_cleanup() {
    for d in "${_CLEANUP_DIRS[@]+"${_CLEANUP_DIRS[@]}"}"; do
        [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
    done
}
trap '_cleanup' EXIT INT TERM

_ok()   { PASS=$((PASS + 1)); printf "  \033[32m✓\033[0m %s\n" "$1"; }
_fail() { FAIL=$((FAIL + 1)); FAILURES+=("$1: $2"); printf "  \033[31m✗\033[0m %s — %s\n" "$1" "$2"; }
_assert_eq() { [[ "$1" == "$2" ]] && _ok "$3" || _fail "$3" "expected '$2', got '$1'"; }

# _new_repo — create a fresh temp git repo; echo its path.
# Writes config directly to avoid 2 extra git-config process spawns per repo.
_new_repo() {
    local d
    d=$(mktemp -d 2>/dev/null || mktemp -d -t lifecycle)
    _CLEANUP_DIRS+=("$d")
    git init -q "$d"
    printf '[user]\n\temail = t@t\n\tname = t\n' >> "$d/.git/config"
    echo "$d"
}

# _new_tmp — a non-git temp dir.
_new_tmp() {
    local d
    d=$(mktemp -d 2>/dev/null || mktemp -d -t lifecycle)
    _CLEANUP_DIRS+=("$d")
    echo "$d"
}

# _scaffold <repo> [args...] — run init-artifacts in repo; fail loudly on error.
# Captures output and checks the exit status so a scaffold failure (missing
# templates, bad DOTFILES, …) surfaces as one clear failure instead of hiding
# behind noisier downstream assertion errors.
_scaffold() {
    local repo="$1"; shift
    local out ec
    out=$(cd "$repo" && DOTFILES="$DOTFILES" bash "$INIT" "$@" </dev/null 2>&1); ec=$?
    if [[ $ec -ne 0 ]]; then
        _fail "init-artifacts scaffold" "exit $ec: $out"
        return "$ec"
    fi
}

# _run <repo> <cmd...> — run cmd in repo; sets globals OUT and EC.
# stdin is /dev/null so an interactive command (update-artifacts prompts on
# drift) gets EOF instead of blocking the test run.
_run() {
    local repo="$1"; shift
    OUT=$( cd "$repo" && DOTFILES="$DOTFILES" "$@" </dev/null 2>&1 )
    EC=$?
}

echo ""
echo "Artifact lifecycle integration tests"
echo "════════════════════════════════════════════════"

# ─── Group 1: shell syntax + init-artifacts + ignore/tracked + plan discovery ─
_group_init() {
echo ""
echo "── shell syntax ──"
for s in "$INIT" "$UPDATE" "$AUDIT"; do
    if bash -n "$s" 2>/dev/null; then _ok "syntax ok: $(basename "$s")"; else _fail "syntax: $(basename "$s")" "bash -n failed"; fi
done

# ─── init-artifacts ───────────────────────────────────────────────────────────
echo ""
echo "── init-artifacts ──"
repo=$(_new_repo)
_run "$repo" bash "$INIT" --gitignore
_assert_eq "$EC" 0 "init-artifacts --gitignore exits 0"
for lane in working/active working/refs working/research working/runtime working/tmp working/logs \
            plans plans/issues docs/adr docs/reference docs/research docs/audits; do
    [[ -d "$repo/$lane" ]] && _ok "creates $lane/" || _fail "creates $lane/" "directory missing"
done
[[ -f "$repo/docs/ARTIFACT-LIFECYCLE.md" ]] && _ok "creates docs/ARTIFACT-LIFECYCLE.md" || _fail "creates docs/ARTIFACT-LIFECYCLE.md" "missing"
[[ -f "$repo/working/active/README.md" ]] && _ok "creates lane README files" || _fail "creates lane README files" "working/active/README.md missing"

# idempotency
_run "$repo" bash "$INIT" --gitignore
_assert_eq "$EC" 0 "idempotent re-run exits 0"
printf '%s' "$OUT" | grep -qiE 'skip' && _ok "idempotent re-run skips existing files" || _fail "idempotent re-run skips existing files" "no 'skip' in output"

# --dry-run makes no changes
dry=$(_new_repo)
_run "$dry" bash "$INIT" --dry-run
_assert_eq "$EC" 0 "--dry-run exits 0"
[[ ! -d "$dry/working/active" ]] && _ok "--dry-run creates nothing" || _fail "--dry-run creates nothing" "working/active was created"

# --gitignore adds runtime rules
[[ -f "$repo/.gitignore" ]] && grep -qF "working/runtime/" "$repo/.gitignore" \
    && _ok "--gitignore adds runtime lane rules" || _fail "--gitignore adds runtime lane rules" ".gitignore missing working/runtime/"

# --force overwrites edited template
echo "USER DRIFT" > "$repo/working/active/README.md"
_run "$repo" bash "$INIT" --force
_readme="$repo/working/active/README.md"
# grep exit codes: 0 = marker present (still drifted), 1 = marker absent
# (overwritten — the only pass), 2+ = read error. A bare `! grep` would accept
# the error case as success, so require the file to exist, be non-empty and
# readable, and grep to be exactly 1.
grep -qF "USER DRIFT" "$_readme" 2>/dev/null; _grep_ec=$?
if [[ -s "$_readme" && -r "$_readme" && "$_grep_ec" -eq 1 ]]; then
    _ok "--force overwrites edited README"
else
    _fail "--force overwrites edited README" "missing/empty/unreadable or marker remains (grep exit $_grep_ec)"
fi

# refuses outside a git repo
nongit=$(_new_tmp)
_run "$nongit" bash "$INIT"
[[ "$EC" -ne 0 ]] && _ok "refuses to run outside a git repo" || _fail "refuses to run outside a git repo" "exit $EC"

# ─── ignore + tracked lanes ───────────────────────────────────────────────────
echo ""
echo "── ignore + tracked lanes ──"
git -C "$repo" check-ignore -q working/runtime/x.tmp \
    && _ok "runtime lane (working/runtime) is gitignored" || _fail "runtime lane gitignored" "working/runtime not ignored"
if git -C "$repo" check-ignore -q working/active/x.md; then
    _fail "active lane tracked (not ignored)" "working/active is ignored"
else
    _ok "agent-useful lane (working/active) is tracked"
fi
if git -C "$repo" check-ignore -q working/note.md; then
    _fail "working/ not blanket-ignored" "working/ is blanket-ignored"
else
    _ok "working/ is not blanket-ignored"
fi

# ─── working/active plan discovery ────────────────────────────────────────────
echo ""
echo "── working/active plan discovery ──"
# The gate only adopts a working/active plan that references the current repo
# (by git-root path or repo name), so embed both into the plan body.
repo_name=$(basename "$repo")
cat > "$repo/working/active/myplan.md" <<PLAN
# My Plan for $repo_name

Target repo: $repo

## Context
Work happening in $repo_name.

## Implementation
impl
PLAN
plan_out=$(printf '%s' "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"mkdir -p src/x\"},\"cwd\":\"$repo\"}" \
    | DOTFILES="$DOTFILES" bash "$PLAN_GATE" 2>&1)
if printf '%s' "$plan_out" | grep -qiE 'myplan|PLAN REVIEW'; then
    _ok "plan in working/active is discovered by plan-quality-gate"
else
    _fail "plan in working/active is discovered" "got: $plan_out"
fi
}

# ─── Group 2: update-artifacts ────────────────────────────────────────────────
_group_update() {
echo ""
echo "── update-artifacts ──"
bare=$(_new_repo)
_run "$bare" bash "$UPDATE"
[[ "$EC" -ne 0 ]] && _ok "errors when working/ is absent" || _fail "errors when working/ is absent" "exit $EC"
printf '%s' "$OUT" | grep -qiE 'init-artifacts' && _ok "points to init-artifacts" || _fail "points to init-artifacts" "no hint in output"

fresh=$(_new_repo); _scaffold "$fresh" --gitignore
_run "$fresh" bash "$UPDATE"
printf '%s' "$OUT" | grep -qiE 'Up to date' && _ok "reports up-to-date on a clean scaffold" || _fail "reports up-to-date on a clean scaffold" "got: $OUT"

echo "DRIFTED TEMPLATE CONTENT" > "$fresh/working/README.md"
_run "$fresh" bash "$UPDATE" --dry-run
_assert_eq "$EC" 0 "update-artifacts --dry-run exits 0 with drift present"
printf '%s' "$OUT" | grep -qF "working/README.md" \
    && _ok "detects a drifted template (reports working/README.md)" \
    || _fail "detects a drifted template" "working/README.md not reported; got: $OUT"
}

# ─── Group 3: artifact-lifecycle-audit ────────────────────────────────────────
_group_audit() {
echo ""
echo "── artifact-lifecycle-audit ──"
nongit=$(_new_tmp)
audrepo=$(_new_repo); _scaffold "$audrepo" --gitignore
_run "$audrepo" bash "$AUDIT"
_assert_eq "$EC" 0 "audit passes on a clean scaffold (warn-only)"
_run "$audrepo" bash "$AUDIT" --strict
_assert_eq "$EC" 0 "audit --strict passes on a clean scaffold"

echo "loose content" > "$audrepo/working/loose.md"
_run "$audrepo" bash "$AUDIT"
printf '%s' "$OUT" | grep -qiE 'loose' && _ok "warns on a loose file in working/ root" || _fail "warns on a loose file in working/ root" "no warning"
rm -f "$audrepo/working/loose.md"

noign=$(_new_repo); _scaffold "$noign"   # scaffold WITHOUT --gitignore → runtime lanes not ignored
_run "$noign" bash "$AUDIT" --strict
[[ "$EC" -ne 0 ]] && _ok "audit --strict fails when runtime lanes are not gitignored" || _fail "audit --strict fails when runtime lanes not ignored" "exit $EC"

_run "$nongit" bash "$AUDIT"
[[ "$EC" -ne 0 ]] && _ok "audit errors outside a git repo" || _fail "audit errors outside a git repo" "exit $EC"
}

# ─── Parallel harness ────────────────────────────────────────────────────────
_PAR_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t lifecycle-par)
_CLEANUP_DIRS+=("$_PAR_DIR")

_GROUPS=(_group_init _group_update _group_audit)
_PIDS=()

for _g in "${_GROUPS[@]}"; do
    (
        PASS=0; FAIL=0; FAILURES=()
        _CLEANUP_DIRS=()
        _GRP_NAME="$_g"
        _GRP_DIR="$_PAR_DIR"
        _grp_exit() {
            set +e
            echo "$PASS" > "$_GRP_DIR/$_GRP_NAME.pass"
            echo "$FAIL" > "$_GRP_DIR/$_GRP_NAME.fail"
            printf '%s\n' "${FAILURES[@]+"${FAILURES[@]}"}" > "$_GRP_DIR/$_GRP_NAME.failures"
            _cleanup
        }
        _grp_signal_exit() {
            trap - EXIT INT TERM
            _grp_exit
            exit 130
        }
        trap '_grp_exit' EXIT
        trap '_grp_signal_exit' INT TERM
        "$_g"
    ) > "$_PAR_DIR/$_g.out" 2>&1 &
    _PIDS+=($!)
done

_kill_groups() {
    for _pid in "${_PIDS[@]}"; do kill "$_pid" 2>/dev/null || true; done
    wait
    exit 1
}
trap '_kill_groups' INT TERM

for _pid in "${_PIDS[@]}"; do
    wait "$_pid" || true
done

# Replay output in order and aggregate results
PASS=0; FAIL=0; FAILURES=()
for _g in "${_GROUPS[@]}"; do
    cat "$_PAR_DIR/$_g.out"
    PASS=$((PASS + $(<"$_PAR_DIR/$_g.pass")))
    FAIL=$((FAIL + $(<"$_PAR_DIR/$_g.fail")))
    while IFS= read -r _f; do
        [[ -n "$_f" ]] && FAILURES+=("$_f")
    done < "$_PAR_DIR/$_g.failures"
done
echo ""
echo "════════════════════════════════════════════════"
printf "  \033[32m%d passed\033[0m  \033[31m%d failed\033[0m\n" "$PASS" "$FAIL"
if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo ""
    echo "  Failures:"
    for f in "${FAILURES[@]}"; do printf "    \033[31m✗\033[0m %s\n" "$f"; done
    echo ""
    exit 1
fi
echo ""
exit 0
