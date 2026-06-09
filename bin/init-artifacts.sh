#!/usr/bin/env bash
# init-artifacts.sh — Scaffold the artifact lifecycle in any repo.
#
# Usage: ctrl init-artifacts [--force] [--dry-run] [--gitignore]
#
# Creates lifecycle directories with README files, optionally adds
# .gitignore rules for runtime lanes. Idempotent — refuses to overwrite
# existing files unless --force is passed.
#
# See docs/ARTIFACT-LIFECYCLE.md for the full lifecycle specification.

set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
source "$DOTFILES/bin/_lib.sh"

# ── Defaults ──────────────────────────────────────────────────────────────────
FORCE=false
DRY_RUN=false
ADD_GITIGNORE=false

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)      FORCE=true; shift ;;
        --dry-run)    DRY_RUN=true; shift ;;
        --gitignore)  ADD_GITIGNORE=true; shift ;;
        --help|-h)
            echo "Usage: ctrl init-artifacts [--force] [--dry-run] [--gitignore]"
            echo ""
            echo "Scaffold the artifact lifecycle directories and README files."
            echo ""
            echo "Options:"
            echo "  --force       Overwrite existing README files"
            echo "  --dry-run     Show what would be created without making changes"
            echo "  --gitignore   Add runtime lane ignore rules to .gitignore"
            echo ""
            echo "Creates:"
            echo "  working/active/       Execution plans (tracked)"
            echo "  working/refs/         Reference material (tracked)"
            echo "  working/research/     Exploration artifacts (tracked)"
            echo "  working/runtime/      Auto-generated state (ignored)"
            echo "  working/tmp/          Temporary artifacts (ignored)"
            echo "  working/logs/         Execution logs (ignored)"
            echo "  plans/                PRDs and issue breakdowns"
            echo "  plans/issues/         Issue slice files"
            echo "  docs/adr/             Architecture Decision Records"
            echo "  docs/reference/       Durable reference material"
            echo "  docs/research/        Promoted research"
            echo "  docs/audits/          Assessment artifacts"
            echo "  docs/ARTIFACT-LIFECYCLE.md  Lifecycle specification"
            exit 0
            ;;
        *) red "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Verify git repo ──────────────────────────────────────────────────────────
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    red "Not inside a git repository. Run this from a repo root."
    exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# ── Source templates ─────────────────────────────────────────────────────────
TEMPLATES="$DOTFILES/templates/lifecycle"

if [[ ! -d "$TEMPLATES" ]]; then
    red "Lifecycle templates not found at $TEMPLATES"
    exit 1
fi

# ── Helpers ──────────────────────────────────────────────────────────────────
_created=0
_skipped=0
_would_create=0

# Copy a template file if the target doesn't exist (or --force).
# Usage: _copy_template <src_relative> <dest_relative>
_copy_template() {
    local src="$TEMPLATES/$1"
    local dest="$REPO_ROOT/$2"
    local dest_dir
    dest_dir="$(dirname "$dest")"

    if [[ ! -f "$src" ]]; then
        red "  Template missing: $1"
        return 1
    fi

    if [[ "$DRY_RUN" == true ]]; then
        if [[ -f "$dest" ]] && [[ "$FORCE" != true ]]; then
            yellow "  [skip] $2 (exists)"
            _skipped=$((_skipped + 1))
        else
            echo "  [create] $2"
            _would_create=$((_would_create + 1))
        fi
        return 0
    fi

    if [[ -f "$dest" ]] && [[ "$FORCE" != true ]]; then
        yellow "  $2 exists — skipping"
        _skipped=$((_skipped + 1))
        return 0
    fi

    mkdir -p "$dest_dir"
    cp "$src" "$dest"
    echo "    $2"
    _created=$((_created + 1))
}

# ── Banner ───────────────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == true ]]; then
    yellow "Dry run — no files will be created."
    echo ""
fi

green "Initializing artifact lifecycle in $(basename "$REPO_ROOT")..."
echo ""

# ── 1. Create tracked working/ lanes ────────────────────────────────────────
echo "  Tracked working lanes:"
_copy_template "working/README.md"          "working/README.md"
_copy_template "working/active/README.md"   "working/active/README.md"
_copy_template "working/refs/README.md"     "working/refs/README.md"
_copy_template "working/research/README.md" "working/research/README.md"

# ── 2. Create ignored working/ lanes (directories only, no README) ──────────
echo "  Runtime lanes:"
for lane in "working/runtime" "working/tmp" "working/logs"; do
    lane_path="$REPO_ROOT/$lane"
    if [[ "$DRY_RUN" == true ]]; then
        if [[ -d "$lane_path" ]]; then
            yellow "  [skip] $lane (exists)"
            _skipped=$((_skipped + 1))
        else
            echo "  [create] $lane"
            _would_create=$((_would_create + 1))
        fi
    else
        if [[ -d "$lane_path" ]]; then
            yellow "  $lane exists — skipping"
            _skipped=$((_skipped + 1))
        else
            mkdir -p "$lane_path"
            echo "    $lane"
            _created=$((_created + 1))
        fi
    fi
done

# ── 3. Create plans/ ────────────────────────────────────────────────────────
echo "  Plans:"
_copy_template "plans/README.md"        "plans/README.md"
_copy_template "plans/issues/README.md" "plans/issues/README.md"

# ── 4. Create docs/ permanent directories ───────────────────────────────────
echo "  Docs:"
_copy_template "docs/ARTIFACT-LIFECYCLE.md" "docs/ARTIFACT-LIFECYCLE.md"
_copy_template "docs/adr/README.md"         "docs/adr/README.md"
_copy_template "docs/reference/README.md"   "docs/reference/README.md"
_copy_template "docs/research/README.md"    "docs/research/README.md"
_copy_template "docs/audits/README.md"      "docs/audits/README.md"

# ── 5. Add .gitignore rules (optional) ──────────────────────────────────────
if [[ "$ADD_GITIGNORE" == true ]]; then
    echo ""
    echo "  Gitignore rules:"

    GITIGNORE="$REPO_ROOT/.gitignore"
    _MARKER="# Artifact lifecycle — ignored runtime lanes"

    if [[ "$DRY_RUN" == true ]]; then
        if [[ -f "$GITIGNORE" ]] && grep -qF "$_MARKER" "$GITIGNORE"; then
            yellow "  [skip] .gitignore rules already present"
        else
            echo "  [create] .gitignore runtime lane rules"
            _would_create=$((_would_create + 1))
        fi
    else
        if [[ -f "$GITIGNORE" ]] && grep -qF "$_MARKER" "$GITIGNORE"; then
            yellow "  .gitignore rules already present — skipping"
            _skipped=$((_skipped + 1))
        else
            {
                echo ""
                echo "$_MARKER"
                echo "# Never blanket-ignore working/ — only specific subdirectories containing runtime noise."
                echo "working/runtime/"
                echo "working/tmp/"
                echo "working/logs/"
            } >> "$GITIGNORE"
            echo "    Added runtime lane rules to .gitignore"
            _created=$((_created + 1))
        fi
    fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
if [[ "$DRY_RUN" == true ]]; then
    green "Dry run complete: $_would_create would be created, $_skipped would be skipped."
else
    green "Artifact lifecycle initialized: $_created created, $_skipped skipped."
    echo ""
    echo "  Next steps:"
    echo "  ─────────────────────────────────────────────────────────"
    if [[ "$ADD_GITIGNORE" != true ]]; then
        echo "  1. Add gitignore rules for runtime lanes:"
        echo "     ctrl init-artifacts --gitignore"
        echo "     (or add manually: working/runtime/, working/tmp/, working/logs/)"
        echo ""
        echo "  2. Commit the scaffolded files:"
    else
        echo "  1. Commit the scaffolded files:"
    fi
    echo "     git add working/ plans/ docs/"
    echo "     git commit -m 'chore: scaffold artifact lifecycle'"
    echo ""
    echo "  Run 'ctrl lifecycle-audit' to verify placement compliance."
fi
