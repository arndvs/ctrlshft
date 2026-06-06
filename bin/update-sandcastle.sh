#!/usr/bin/env bash
# update-sandcastle.sh — Detect drift and sync Sandcastle framework files.
#
# Compares the vendored .sandcastle/ against the framework source in shft/
# and updates engine-owned files. User-customizable files (prompts) are left
# untouched unless --prompts is passed.
#
# Usage:
#   bash bin/update-sandcastle.sh [TARGET_DIR] [--dry-run] [--workflows] [--prompts] [--help]
#
# If TARGET_DIR is omitted, defaults to the current working directory.
#
# Exit code: 0 on success (or no drift), 1 on failure.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
SHFT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../shft" && pwd)"
TEMPLATES_DIR="$SHFT_DIR/templates"
ENGINE_DIR="$SHFT_DIR/engine"

# ── Defaults ─────────────────────────────────────────────────────────────────
TARGET_DIR=""
DRY_RUN=0
UPDATE_WORKFLOWS=0
UPDATE_PROMPTS=0

# ── Arg parsing ──────────────────────────────────────────────────────────────
for arg in "$@"; do
    case "$arg" in
        --help|-h)
            echo ""
            echo "  update-sandcastle — Detect drift and sync framework files"
            echo ""
            echo "  Usage: ctrl update-sandcastle [TARGET_DIR] [--dry-run] [--workflows] [--prompts]"
            echo ""
            echo "  Arguments:"
            echo "    TARGET_DIR          Path to the target repo (default: current directory)"
            echo "    --dry-run           Show what would change without modifying files"
            echo "    --workflows         Also update .github/workflows/ (may overwrite customizations)"
            echo "    --prompts           Also update .sandcastle/prompts/ (may overwrite customizations)"
            echo "    --help              Show this help message"
            echo ""
            echo "  Always updated (engine-owned):"
            echo "    .sandcastle/run.ts"
            echo "    .sandcastle/extractions/"
            echo "    .sandcastle/hooks/"
            echo "    .sandcastle/sandbox/"
            echo "    .sandcastle/scripts/"
            echo "    .sandcastle/labels.json"
            echo "    .sandcastle/node_modules/.sandcastle-engine/"
            echo ""
            echo "  Updated only with flags:"
            echo "    --workflows   .github/workflows/agent-*.yml"
            echo "    --prompts     .sandcastle/prompts/"
            echo ""
            exit 0
            ;;
        --dry-run)      DRY_RUN=1 ;;
        --workflows)    UPDATE_WORKFLOWS=1 ;;
        --prompts)      UPDATE_PROMPTS=1 ;;
        *)
            if [[ -z "$TARGET_DIR" ]]; then
                TARGET_DIR="$arg"
            else
                red "Unknown argument: $arg"
                exit 1
            fi
            ;;
    esac
done

TARGET_DIR="${TARGET_DIR:-.}"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

# ── Validations ──────────────────────────────────────────────────────────────
if [[ ! -d "$TARGET_DIR/.sandcastle" ]]; then
    red "  ✗ No .sandcastle/ found in $TARGET_DIR"
    echo "  Run 'ctrl init-sandcastle' to set up Sandcastle first."
    exit 1
fi

if [[ ! -d "$TEMPLATES_DIR" ]]; then
    red "  ✗ Templates directory not found: $TEMPLATES_DIR"
    exit 1
fi

_mode="UPDATE"
if [[ $DRY_RUN -eq 1 ]]; then
    _mode="DRY RUN"
fi

green "update-sandcastle [$_mode] — checking $TARGET_DIR"
echo ""

_sc="$TARGET_DIR/.sandcastle"
_updated=0
_skipped=0

# ── Helper: sync a single file ──────────────────────────────────────────────
_sync_file() {
    local src="$1" dest="$2" label="$3"

    if [[ ! -f "$src" ]]; then
        return
    fi

    if [[ ! -f "$dest" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            yellow "  + $label (new)"
        else
            mkdir -p "$(dirname "$dest")"
            cp "$src" "$dest"
            green "  + $label (new)"
        fi
        _updated=$((_updated + 1))
        return
    fi

    if ! cmp -s "$src" "$dest"; then
        if [[ $DRY_RUN -eq 1 ]]; then
            yellow "  ~ $label (changed)"
            diff --unified=1 "$dest" "$src" 2>/dev/null | head -20 || true
        else
            cp "$src" "$dest"
            green "  ✓ $label (updated)"
        fi
        _updated=$((_updated + 1))
    else
        _skipped=$((_skipped + 1))
    fi
}

# ── Helper: sync a directory ────────────────────────────────────────────────
_sync_dir() {
    local src_dir="$1" dest_dir="$2" label="$3"

    if [[ ! -d "$src_dir" ]]; then
        return
    fi

    for src_file in "$src_dir"/*; do
        [[ -f "$src_file" ]] || continue
        _name=$(basename "$src_file")
        _sync_file "$src_file" "$dest_dir/$_name" "$label/$_name"
    done
}

# ── Engine-owned files (always updated) ──────────────────────────────────────
echo "Engine-owned files:"

_sync_file "$TEMPLATES_DIR/run.ts" "$_sc/run.ts" "run.ts"
_sync_file "$TEMPLATES_DIR/labels.json" "$_sc/labels.json" "labels.json"
_sync_dir "$TEMPLATES_DIR/extractions" "$_sc/extractions" "extractions"
_sync_dir "$TEMPLATES_DIR/hooks" "$_sc/hooks" "hooks"
_sync_dir "$TEMPLATES_DIR/scripts" "$_sc/scripts" "scripts"

# Sandbox directory
for sf in "$TEMPLATES_DIR/sandbox/"*; do
    [[ -f "$sf" ]] || continue
    _name=$(basename "$sf")
    _sync_file "$sf" "$_sc/sandbox/$_name" "sandbox/$_name"
done

# ── Vendor engine ────────────────────────────────────────────────────────────
echo ""
echo "Engine source:"

_engine_dest="$_sc/node_modules/.sandcastle-engine"

for item in main.ts; do
    _sync_file "$ENGINE_DIR/$item" "$_engine_dest/$item" "engine/$item"
done

for dir in lib schemas workflows prompts; do
    if [[ -d "$ENGINE_DIR/$dir" ]]; then
        for src_file in "$ENGINE_DIR/$dir"/*; do
            [[ -f "$src_file" ]] || continue
            _name=$(basename "$src_file")
            # Skip test files — not needed in vendored copy
            case "$_name" in
                *.test.ts|*.spec.ts) continue ;;
            esac
            _sync_file "$src_file" "$_engine_dest/$dir/$_name" "engine/$dir/$_name"
        done
    fi
done

# ── Workflows (opt-in) ──────────────────────────────────────────────────────
echo ""
if [[ $UPDATE_WORKFLOWS -eq 1 ]]; then
    echo "Workflows (--workflows):"

    # Detect default branch from config or git
    _default_branch=""
    if [[ -f "$TARGET_DIR/sandcastle.config.json" ]]; then
        _default_branch=$(python3 -c "import json; print(json.load(open('$TARGET_DIR/sandcastle.config.json')).get('defaultBranch', ''))" 2>/dev/null || true)
    fi
    if [[ -z "$_default_branch" ]]; then
        _default_branch=$(git -C "$TARGET_DIR" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo "main")
    fi

    _wf_dir="$TARGET_DIR/.github/workflows"
    mkdir -p "$_wf_dir"

    for wf in "$TEMPLATES_DIR/workflows/"*.yml; do
        _name=$(basename "$wf")
        _tmp=$(mktemp)
        sed "s/{{DEFAULT_BRANCH}}/$_default_branch/g" "$wf" > "$_tmp"

        if [[ ! -f "$_wf_dir/$_name" ]]; then
            if [[ $DRY_RUN -eq 1 ]]; then
                yellow "  + $_name (new)"
            else
                cp "$_tmp" "$_wf_dir/$_name"
                green "  + $_name (new)"
            fi
            _updated=$((_updated + 1))
        elif ! cmp -s "$_tmp" "$_wf_dir/$_name"; then
            if [[ $DRY_RUN -eq 1 ]]; then
                yellow "  ~ $_name (changed)"
            else
                cp "$_tmp" "$_wf_dir/$_name"
                green "  ✓ $_name (updated)"
            fi
            _updated=$((_updated + 1))
        else
            _skipped=$((_skipped + 1))
        fi

        rm -f "$_tmp"
    done
else
    echo "Workflows: skipped (pass --workflows to update)"
fi

# ── Prompts (opt-in) ────────────────────────────────────────────────────────
echo ""
if [[ $UPDATE_PROMPTS -eq 1 ]]; then
    echo "Prompts (--prompts):"
    _sync_dir "$TEMPLATES_DIR/prompts" "$_sc/prompts" "prompts"
else
    echo "Prompts: skipped (pass --prompts to update)"
fi

# ── Verify tokens ────────────────────────────────────────────────────────────
if [[ $DRY_RUN -eq 0 ]] && [[ -f "$_sc/scripts/check-file-tokens.sh" ]]; then
    echo ""
    echo "Verifying template tokens:"
    if bash "$_sc/scripts/check-file-tokens.sh" "$_sc" 2>/dev/null; then
        green "  ✓ All template tokens replaced"
    else
        yellow "  ~ Some tokens may need manual replacement"
    fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
if [[ $_updated -eq 0 ]]; then
    green "No drift detected. Everything is up to date."
else
    if [[ $DRY_RUN -eq 1 ]]; then
        yellow "$_updated file(s) would be updated. Run without --dry-run to apply."
    else
        green "$_updated file(s) updated, $_skipped unchanged."
        echo ""
        echo "  Next steps:"
        echo "    1. cd $_sc && npm install   (if engine dependencies changed)"
        echo "    2. Review and commit the changes"
    fi
fi
