#!/usr/bin/env bash
# artifact-lifecycle-audit.sh — Audit artifact placement and lifecycle compliance.
#
# Checks placement, gitignore rules, provenance, and lifecycle anti-patterns
# against the canonical spec in docs/ARTIFACT-LIFECYCLE.md.
#
# Usage:
#   bash ~/dotfiles/bin/artifact-lifecycle-audit.sh          # warn-only (exit 0)
#   bash ~/dotfiles/bin/artifact-lifecycle-audit.sh --strict  # exit 1 on violations
#
# Exit code:
#   0 when all checks pass (or warn-only mode with only warnings)
#   1 when any violation found in --strict mode, or on hard errors

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

# ── State ────────────────────────────────────────────────────────────────────
_strict=0
_warn=0
_fail=0
_pass=0

# ── Parse args ───────────────────────────────────────────────────────────────
for arg in "$@"; do
    case "$arg" in
        --strict) _strict=1 ;;
        *)
            red "Unknown option: $arg"
            echo "Usage: artifact-lifecycle-audit.sh [--strict]"
            exit 1
            ;;
    esac
done

# ── Resolve repo root ───────────────────────────────────────────────────────
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    red "Not inside a git repository."
    exit 1
}

# ── Helpers ──────────────────────────────────────────────────────────────────
_check_pass() { green "  ✓ $1"; _pass=$((_pass + 1)); }
_check_warn() { yellow "  ~ $1"; _warn=$((_warn + 1)); }
_check_fail() { red "  ✗ $1"; _fail=$((_fail + 1)); }

# Test if a path would be gitignored. Returns 0 if ignored, 1 if tracked.
# Paths are resolved relative to REPO_ROOT.
_is_ignored() {
    git check-ignore -q "$REPO_ROOT/$1" 2>/dev/null
}

# ── 1. Placement: loose files in working/ root ──────────────────────────────
echo "Placement:"

_loose_working=()
if [[ -d "$REPO_ROOT/working" ]]; then
    while IFS= read -r f; do
        # Skip README.md — it's legitimate
        [[ "$(basename "$f")" == "README.md" ]] && continue
        # Skip gitignored files — they're runtime noise handled correctly
        rel="${f#"$REPO_ROOT/"}"
        _is_ignored "$rel" && continue
        _loose_working+=("$f")
    done < <(find "$REPO_ROOT/working" -maxdepth 1 -type f -name "*.md" 2>/dev/null)
fi

if [[ ${#_loose_working[@]} -eq 0 ]]; then
    _check_pass "No loose files in working/ root"
else
    _check_warn "Loose files in working/ root (should be in sublanes):"
    for f in "${_loose_working[@]}"; do
        yellow "      $(basename "$f")"
    done
fi

# ── 2. Placement: non-standard directories in working/ ──────────────────────
_valid_lanes=("active" "refs" "research" "runtime" "tmp" "logs")
_nonstandard_dirs=()

if [[ -d "$REPO_ROOT/working" ]]; then
    while IFS= read -r d; do
        dirname="$(basename "$d")"
        _is_known=0
        for lane in "${_valid_lanes[@]}"; do
            if [[ "$dirname" == "$lane" ]]; then
                _is_known=1
                break
            fi
        done
        if [[ $_is_known -eq 0 ]]; then
            _nonstandard_dirs+=("$dirname")
        fi
    done < <(find "$REPO_ROOT/working" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
fi

if [[ ${#_nonstandard_dirs[@]} -eq 0 ]]; then
    _check_pass "No non-standard directories in working/"
else
    _check_warn "Non-standard directories in working/ (not in lifecycle spec):"
    for d in "${_nonstandard_dirs[@]}"; do
        yellow "      working/$d/"
    done
fi

# ── 3. Placement: plans misplaced in docs/ root ─────────────────────────────
_plans_in_docs=()
if [[ -d "$REPO_ROOT/docs" ]]; then
    while IFS= read -r f; do
        fname="$(basename "$f")"
        # Skip known permanent docs
        [[ "$fname" == "ARCHITECTURE.md" ]] && continue
        [[ "$fname" == "ARTIFACT-LIFECYCLE.md" ]] && continue
        [[ "$fname" == "README.md" ]] && continue
        # Flag plan-shaped files (contain "plan" in name)
        if [[ "$fname" == *plan* ]] || [[ "$fname" == *Plan* ]]; then
            _plans_in_docs+=("$fname")
        fi
    done < <(find "$REPO_ROOT/docs" -maxdepth 1 -type f -name "*.md" 2>/dev/null)
fi

if [[ ${#_plans_in_docs[@]} -eq 0 ]]; then
    _check_pass "No plan-shaped files in docs/ root"
else
    _check_warn "Plan-shaped files in docs/ root (plans belong in working/active/ or plans/):"
    for f in "${_plans_in_docs[@]}"; do
        yellow "      docs/$f"
    done
fi

# ── 4. Placement: audit artifacts in docs/ root ─────────────────────────────
_audits_in_docs_root=()
if [[ -d "$REPO_ROOT/docs" ]]; then
    while IFS= read -r f; do
        fname="$(basename "$f")"
        [[ "$fname" == "ARCHITECTURE.md" ]] && continue
        [[ "$fname" == "ARTIFACT-LIFECYCLE.md" ]] && continue
        [[ "$fname" == "README.md" ]] && continue
        # Flag audit-shaped files
        if [[ "$fname" == *audit* ]] || [[ "$fname" == *Audit* ]]; then
            _audits_in_docs_root+=("$fname")
        fi
    done < <(find "$REPO_ROOT/docs" -maxdepth 1 -type f -name "*.md" 2>/dev/null)
fi

if [[ ${#_audits_in_docs_root[@]} -eq 0 ]]; then
    _check_pass "No audit artifacts misplaced in docs/ root"
else
    _check_warn "Audit artifacts in docs/ root (should be in docs/audits/):"
    for f in "${_audits_in_docs_root[@]}"; do
        yellow "      docs/$f"
    done
fi

# ── 5. Placement: stale files under plans/ ───────────────────────────────────
_plans_files=()
if [[ -d "$REPO_ROOT/plans" ]]; then
    while IFS= read -r f; do
        [[ "$(basename "$f")" == "README.md" ]] && continue
        _plans_files+=("$(echo "$f" | sed "s|$REPO_ROOT/||")")
    done < <(find "$REPO_ROOT/plans" -type f -name "*.md" 2>/dev/null)
fi

if [[ ${#_plans_files[@]} -eq 0 ]]; then
    _check_pass "No stale files under plans/"
else
    _check_warn "Files under plans/ (archive or delete after work completes):"
    for f in "${_plans_files[@]}"; do
        yellow "      $f"
    done
fi

# ── 6. Ignore rules: runtime lanes must be gitignored ────────────────────────
echo ""
echo "Ignore Rules:"

_runtime_lanes=("working/runtime/test.tmp" "working/tmp/test.tmp" "working/logs/test.log")
_runtime_not_ignored=()

for path in "${_runtime_lanes[@]}"; do
    if ! _is_ignored "$path"; then
        _runtime_not_ignored+=("$(dirname "$path")/")
    fi
done

if [[ ${#_runtime_not_ignored[@]} -eq 0 ]]; then
    _check_pass "Runtime lanes (runtime/, tmp/, logs/) are gitignored"
else
    _check_fail "Runtime lanes NOT gitignored (should be ignored):"
    for p in "${_runtime_not_ignored[@]}"; do
        red "      $p"
    done
fi

# ── 7. Ignore rules: agent-useful lanes must NOT be gitignored ───────────────
_tracked_lanes=("working/active/test.md" "working/refs/test.md" "working/research/test.md")
_tracked_ignored=()

for path in "${_tracked_lanes[@]}"; do
    if _is_ignored "$path"; then
        _tracked_ignored+=("$(dirname "$path")/")
    fi
done

if [[ ${#_tracked_ignored[@]} -eq 0 ]]; then
    _check_pass "Agent-useful lanes (active/, refs/, research/) are tracked"
else
    _check_fail "Agent-useful lanes are gitignored (should be tracked):"
    for p in "${_tracked_ignored[@]}"; do
        red "      $p"
    done
fi

# ── 8. Ignore rules: working/ itself is not blanket-ignored ──────────────────
if _is_ignored "working/test-file.md"; then
    _check_fail "working/ is blanket-ignored (violates discoverability rule)"
else
    _check_pass "working/ is not blanket-ignored"
fi

# ── 9. Provenance: refs must have Source/Fetched/Context ─────────────────────
echo ""
echo "Provenance:"

_refs_missing_provenance=()
if [[ -d "$REPO_ROOT/working/refs" ]]; then
    while IFS= read -r f; do
        [[ "$(basename "$f")" == "README.md" ]] && continue
        _missing=()
        grep -qi "^Source:" "$f" 2>/dev/null || _missing+=("Source")
        grep -qi "^Fetched:" "$f" 2>/dev/null || _missing+=("Fetched")
        grep -qi "^Context:" "$f" 2>/dev/null || _missing+=("Context")
        if [[ ${#_missing[@]} -gt 0 ]]; then
            _refs_missing_provenance+=("$(basename "$f") (missing: ${_missing[*]})")
        fi
    done < <(find "$REPO_ROOT/working/refs" -type f -name "*.md" 2>/dev/null)
fi

if [[ ${#_refs_missing_provenance[@]} -eq 0 ]]; then
    _check_pass "All refs have provenance metadata"
else
    _check_warn "Refs missing provenance (need Source, Fetched, Context):"
    for r in "${_refs_missing_provenance[@]}"; do
        yellow "      $r"
    done
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
_total=$((_pass + _warn + _fail))
if [[ $_fail -eq 0 ]] && [[ $_warn -eq 0 ]]; then
    green "✓ All $_total checks passed."
    exit 0
elif [[ $_fail -eq 0 ]]; then
    yellow "~ $_pass passed, $_warn warnings."
    if [[ $_strict -eq 1 ]]; then
        echo ""
        yellow "Strict mode: exiting with code 1 due to warnings."
        exit 1
    fi
    exit 0
else
    red "✗ $_pass passed, $_warn warnings, $_fail failures."
    exit 1
fi
