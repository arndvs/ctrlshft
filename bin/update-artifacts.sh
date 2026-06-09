#!/usr/bin/env bash
# update-artifacts.sh — Detect drift between a repo's lifecycle files and the
# canonical templates in ~/dotfiles/templates/lifecycle/.
#
# Usage: ctrl update-artifacts [--dry-run]
#
# Checks:
#   1. Lifecycle README templates (11 files) — missing or changed
#   2. .gitignore runtime lane rules — missing marker block or entries
#   3. .ctrlshft active_plans_dir key — missing advisory when .ctrlshft exists
#
# Does NOT blindly overwrite project-specific edits — shows diffs and prompts
# the user to accept changes selectively.
#
# See docs/ARTIFACT-LIFECYCLE.md for the full lifecycle specification.

set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
source "$DOTFILES/bin/_lib.sh"

DRY_RUN=false

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)  DRY_RUN=true; shift ;;
        --help|-h)
            echo "Usage: ctrl update-artifacts [--dry-run]"
            echo ""
            echo "Detect drift between lifecycle files and dotfiles templates."
            echo ""
            echo "Options:"
            echo "  --dry-run  Show what would change without making changes"
            echo ""
            echo "Checks lifecycle README templates, .gitignore rules, and"
            echo "optional .ctrlshft configuration for drift or missing entries."
            exit 0
            ;;
        *) red "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Verify git repo ──────────────────────────────────────────────────────────
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    red "Not inside a git repository."
    exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# ── Verify lifecycle is initialized ──────────────────────────────────────────
if [[ ! -d "working" ]]; then
    red "No working/ directory found. Run 'ctrl init-artifacts' first."
    exit 1
fi

# ── Source templates ─────────────────────────────────────────────────────────
TEMPLATES="$DOTFILES/templates/lifecycle"

if [[ ! -d "$TEMPLATES" ]]; then
    red "Lifecycle templates not found at $TEMPLATES"
    exit 1
fi

# ── Canonical template manifest ──────────────────────────────────────────────
# All lifecycle files that init-artifacts scaffolds from templates.
# Order matches init-artifacts sections for consistent output.
TEMPLATE_FILES=(
    "working/README.md"
    "working/active/README.md"
    "working/refs/README.md"
    "working/research/README.md"
    "plans/README.md"
    "plans/issues/README.md"
    "docs/ARTIFACT-LIFECYCLE.md"
    "docs/adr/README.md"
    "docs/reference/README.md"
    "docs/research/README.md"
    "docs/audits/README.md"
)

# ── Drift detection ─────────────────────────────────────────────────────────
MISSING_FILES=()
DRIFTED_FILES=()
UPTODATE_FILES=()
DIFF_OUTPUT=""

echo "Checking lifecycle templates..."

for rel in "${TEMPLATE_FILES[@]}"; do
    src="$TEMPLATES/$rel"
    dst="$REPO_ROOT/$rel"

    if [[ ! -f "$src" ]]; then
        # Template itself is missing — skip (shouldn't happen)
        continue
    fi

    if [[ ! -f "$dst" ]]; then
        MISSING_FILES+=("$rel")
        continue
    fi

    if ! diff -q "$src" "$dst" &>/dev/null; then
        DRIFTED_FILES+=("$rel")
        DIFF_OUTPUT+="$(printf '\n── %s ──\n' "$rel")"
        DIFF_OUTPUT+="$(diff -u "$dst" "$src" --label "installed/$rel" --label "template/$rel" 2>/dev/null || true)"
        DIFF_OUTPUT+=$'\n'
    else
        UPTODATE_FILES+=("$rel")
    fi
done

# ── .gitignore check ─────────────────────────────────────────────────────────
_MARKER="# Artifact lifecycle — ignored runtime lanes"
GITIGNORE_MISSING_MARKER=false
GITIGNORE_MISSING_RULES=()
GITIGNORE_RULES=(
    "working/runtime/"
    "working/tmp/"
    "working/logs/"
)

echo "Checking .gitignore rules..."

if [[ ! -f "$REPO_ROOT/.gitignore" ]] || ! grep -qF "$_MARKER" "$REPO_ROOT/.gitignore"; then
    GITIGNORE_MISSING_MARKER=true
fi

for rule in "${GITIGNORE_RULES[@]}"; do
    if [[ ! -f "$REPO_ROOT/.gitignore" ]] || ! grep -qFx "$rule" "$REPO_ROOT/.gitignore"; then
        GITIGNORE_MISSING_RULES+=("$rule")
    fi
done

# ── .ctrlshft check ──────────────────────────────────────────────────────────
CTRLSHFT_MISSING=false

echo "Checking .ctrlshft config..."

if [[ -f "$REPO_ROOT/.ctrlshft" ]] && ! grep -q "active_plans_dir" "$REPO_ROOT/.ctrlshft"; then
    CTRLSHFT_MISSING=true
fi

# ── Report ───────────────────────────────────────────────────────────────────
echo ""

TOTAL_ISSUES=$(( ${#MISSING_FILES[@]} + ${#DRIFTED_FILES[@]} ))

# Missing files
if [[ ${#MISSING_FILES[@]} -gt 0 ]]; then
    yellow "Missing (${#MISSING_FILES[@]}):"
    for f in "${MISSING_FILES[@]}"; do
        echo "  - $f"
    done
    echo ""
fi

# Drifted files
if [[ ${#DRIFTED_FILES[@]} -gt 0 ]]; then
    yellow "Changed (${#DRIFTED_FILES[@]}):"
    for f in "${DRIFTED_FILES[@]}"; do
        echo "  - $f"
    done
    echo ""
fi

# Up-to-date files
if [[ ${#UPTODATE_FILES[@]} -gt 0 ]]; then
    green "Up to date (${#UPTODATE_FILES[@]}):"
    for f in "${UPTODATE_FILES[@]}"; do
        echo "  - $f"
    done
    echo ""
fi

# Config warnings (advisory only — not counted as actionable drift)
if [[ "$GITIGNORE_MISSING_MARKER" == true ]] || [[ ${#GITIGNORE_MISSING_RULES[@]} -gt 0 ]]; then
    yellow "Advisory: .gitignore is missing lifecycle runtime lane rules."
    if [[ "$GITIGNORE_MISSING_MARKER" == true ]]; then
        echo "  Missing marker: $_MARKER"
    fi
    if [[ ${#GITIGNORE_MISSING_RULES[@]} -gt 0 ]]; then
        echo "  Missing rules:"
        for rule in "${GITIGNORE_MISSING_RULES[@]}"; do
            echo "    - $rule"
        done
    fi
    echo "  Run 'ctrl init-artifacts --gitignore' to add them."
    echo ""
fi

if [[ "$CTRLSHFT_MISSING" == true ]]; then
    yellow "Advisory: .ctrlshft is missing 'active_plans_dir' key."
    echo "  Add 'active_plans_dir: working/active' to enable plan discovery."
    echo ""
fi

# Up-to-date summary
if [[ $TOTAL_ISSUES -eq 0 ]]; then
    green "All ${#TEMPLATE_FILES[@]} lifecycle templates are up to date."
    if [[ "$GITIGNORE_MISSING_MARKER" == false ]] && [[ ${#GITIGNORE_MISSING_RULES[@]} -eq 0 ]] && [[ "$CTRLSHFT_MISSING" == false ]]; then
        green "No drift detected."
    fi
    exit 0
fi

echo "${#UPTODATE_FILES[@]} of ${#TEMPLATE_FILES[@]} templates are up to date."
echo ""

# ── Dry run exit ─────────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == true ]]; then
    if [[ -n "$DIFF_OUTPUT" ]]; then
        echo "$DIFF_OUTPUT"
    fi
    yellow "Dry run — no changes made."
    exit 0
fi

# ── Show diffs ───────────────────────────────────────────────────────────────
if [[ -n "$DIFF_OUTPUT" ]]; then
    echo "$DIFF_OUTPUT"
fi

# ── Prompt for update ────────────────────────────────────────────────────────
echo "Options:"
echo "  [a] Update all ($TOTAL_ISSUES file(s))"
echo "  [s] Update selectively (confirm each file)"
echo "  [q] Quit without changes"
echo ""
read -r -p "Choice [a/s/q]: " choice

case "$choice" in
    a|A) echo "" ;;
    s|S) echo "" ;;
    q|Q)
        echo "No changes made."
        exit 0
        ;;
    *)
        red "Invalid choice."
        exit 1
        ;;
esac

# ── Apply updates ────────────────────────────────────────────────────────────
updated=0

apply_file() {
    local src="$1" dst="$2" label="$3"

    if [[ "$choice" == "s" || "$choice" == "S" ]]; then
        read -r -p "  Update $label? [y/n]: " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "    Skipped: $label"
            return
        fi
    fi

    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "    Updated: $label"
    ((updated++)) || true
}

# Apply missing files
for rel in "${MISSING_FILES[@]}"; do
    apply_file "$TEMPLATES/$rel" "$REPO_ROOT/$rel" "$rel"
done

# Apply drifted files
for rel in "${DRIFTED_FILES[@]}"; do
    apply_file "$TEMPLATES/$rel" "$REPO_ROOT/$rel" "$rel"
done

echo ""
green "Updated $updated file(s)."
