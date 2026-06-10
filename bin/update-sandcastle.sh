#!/usr/bin/env bash
# update-sandcastle.sh — Detect drift between vendored Sandcastle files and
# dotfiles source. Shows diffs and prompts the user to update.
#
# Usage: ctrl update-sandcastle [--dry-run]
#
# Checks:
#   1. .sandcastle/engine/ vs ~/dotfiles/shft/engine/ (excluding tests/node_modules)
#   2. .sandcastle/templates/ vs ~/dotfiles/shft/templates/{prompts,extractions}/
#   3. .sandcastle/{scripts,hooks}/ vs ~/dotfiles/shft/templates/{scripts,hooks}/
#   4. .github/workflows/agent-*.yml vs ~/dotfiles/shft/templates/workflows/
#   5. .github/copilot-setup-steps.yml vs ~/dotfiles/shft/templates/copilot-setup-steps.yml
#
# Never touches project-specific files: prompts, config, CODING_STANDARDS.md.

set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
source "$DOTFILES/bin/_lib.sh"

DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)  DRY_RUN=true; shift ;;
        --help|-h)
            echo "Usage: ctrl update-sandcastle [--dry-run]"
            echo ""
            echo "Detects drift between vendored Sandcastle files and dotfiles source."
            echo "  --dry-run  Show what would change without changing anything"
            exit 0
            ;;
        *) red "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Verify context ───────────────────────────────────────────────────────────
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    red "Not inside a git repository."
    exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if [[ ! -d ".sandcastle/engine" ]]; then
    red "No .sandcastle/engine/ found. Run 'ctrl init-sandcastle' first."
    exit 1
fi

TEMPLATES="$DOTFILES/shft/templates"
ENGINE="$DOTFILES/shft/engine"

if [[ ! -d "$ENGINE" ]]; then
    red "Engine source not found at $ENGINE"
    exit 1
fi

render_vendored_engine_package() {
    if ! command -v node &>/dev/null; then
        red "Node.js is required to render .sandcastle/engine/package.json."
        exit 1
    fi

    ENGINE_PACKAGE="$ENGINE/package.json" node <<'NODE'
const fs = require("fs");

const pkg = JSON.parse(fs.readFileSync(process.env.ENGINE_PACKAGE, "utf8"));
pkg.scripts = {
  ...pkg.scripts,
  test: 'echo "Vendored Sandcastle engine excludes test files; run pnpm run typecheck to validate runtime sources."',
};
pkg.pnpm = {
    ...pkg.pnpm,
    onlyBuiltDependencies: ["@parcel/watcher", "esbuild", "msgpackr-extract"],
};

process.stdout.write(`${JSON.stringify(pkg, null, 2)}\n`);
NODE
}

VENDORED_ENGINE_PACKAGE_JSON="$(mktemp)"
trap 'rm -f "$VENDORED_ENGINE_PACKAGE_JSON"' EXIT
render_vendored_engine_package > "$VENDORED_ENGINE_PACKAGE_JSON"

# ── Drift detection ──────────────────────────────────────────────────────────

DRIFTED_FILES=()
DIFF_OUTPUT=""

# Compare a source file against its vendored counterpart.
# Args: $1=source_path $2=vendored_path $3=display_label
check_file() {
    local src="$1" dst="$2" label="$3"
    if [[ ! -f "$dst" ]]; then
        DRIFTED_FILES+=("$label (new — not vendored)")
        DIFF_OUTPUT+="$(printf '\n── %s (new file) ──\n' "$label")"
        return
    fi
    if ! diff -q "$src" "$dst" &>/dev/null; then
        DRIFTED_FILES+=("$label")
        DIFF_OUTPUT+="$(printf '\n── %s ──\n' "$label")"
        DIFF_OUTPUT+="$(diff -u "$dst" "$src" --label "vendored/$label" --label "source/$label" 2>/dev/null || true)"
        DIFF_OUTPUT+=$'\n'
    fi
}

check_dir_files() {
    local src_dir="$1" dst_dir="$2" label_prefix="$3"

    [[ -d "$src_dir" ]] || return
    for src_file in "$src_dir"/*; do
        [[ -f "$src_file" ]] || continue
        local fname
        fname="$(basename "$src_file")"
        check_file "$src_file" "$dst_dir/$fname" "$label_prefix/$fname"
    done
}

# 1. Engine lib files (skip tests)
echo "Checking engine/lib/..."
for src_file in "$ENGINE/lib/"*.ts; do
    fname="$(basename "$src_file")"
    [[ "$fname" == *.test.ts ]] && continue
    check_file "$src_file" ".sandcastle/engine/lib/$fname" "engine/lib/$fname"
done

# Check for removed files in vendored that no longer exist in source
for vendored_file in .sandcastle/engine/lib/*.ts; do
    [[ ! -f "$vendored_file" ]] && continue
    fname="$(basename "$vendored_file")"
    if [[ ! -f "$ENGINE/lib/$fname" ]]; then
        DRIFTED_FILES+=("engine/lib/$fname (removed from source)")
        DIFF_OUTPUT+="$(printf '\n── engine/lib/%s (removed from source) ──\n' "$fname")"
    fi
done

# 2. Engine schemas
echo "Checking engine/schemas/..."
for src_file in "$ENGINE/schemas/"*.ts; do
    [[ ! -f "$src_file" ]] && continue
    fname="$(basename "$src_file")"
    check_file "$src_file" ".sandcastle/engine/schemas/$fname" "engine/schemas/$fname"
done

# 3. Engine workflows
echo "Checking engine/workflows/..."
for src_file in "$ENGINE/workflows/"*.ts; do
    [[ ! -f "$src_file" ]] && continue
    fname="$(basename "$src_file")"
    [[ "$fname" == *.test.ts ]] && continue
    check_file "$src_file" ".sandcastle/engine/workflows/$fname" "engine/workflows/$fname"
done

# 4. Engine package.json + tsconfig.json
echo "Checking engine config files..."
check_file "$VENDORED_ENGINE_PACKAGE_JSON" ".sandcastle/engine/package.json" "engine/package.json"
for cfg in pnpm-lock.yaml tsconfig.json; do
    if [[ -f "$ENGINE/$cfg" ]]; then
        check_file "$ENGINE/$cfg" ".sandcastle/engine/$cfg" "engine/$cfg"
    fi
done

# 5. Runtime prompt and extraction templates
echo "Checking runtime templates..."
check_dir_files "$TEMPLATES/prompts" ".sandcastle/templates/prompts" "templates/prompts"
check_dir_files "$TEMPLATES/extractions" ".sandcastle/templates/extractions" "templates/extractions"

# 6. Helper scripts and hooks
echo "Checking helper scripts and hooks..."
check_dir_files "$TEMPLATES/scripts" ".sandcastle/scripts" "scripts"
check_dir_files "$TEMPLATES/hooks" ".sandcastle/hooks" "hooks"

# 7. Optional sandbox template
SANDBOX="none"
if [[ -f "sandcastle.config.json" ]] && command -v node &>/dev/null; then
    SANDBOX=$(node -e "
        try {
            const c = JSON.parse(require('fs').readFileSync('sandcastle.config.json','utf8'));
            console.log(c.sandbox || 'none');
        } catch { console.log('none'); }
    " 2>/dev/null || echo "none")
fi

if [[ "$SANDBOX" == "docker" || -d ".sandcastle/sandbox" ]]; then
    echo "Checking sandbox template..."
    check_dir_files "$TEMPLATES/sandbox" ".sandcastle/sandbox" "sandbox"
fi

# 8. Workflow YAMLs — need to resolve {{DEFAULT_BRANCH}} before comparing
echo "Checking workflow YAMLs..."

# Read baseBranch from config (default: main)
BASE_BRANCH="main"
PM="pnpm"
if [[ -f "sandcastle.config.json" ]] && command -v node &>/dev/null; then
    BASE_BRANCH=$(node -e "
        try {
            const c = JSON.parse(require('fs').readFileSync('sandcastle.config.json','utf8'));
            console.log(c.baseBranch || 'main');
        } catch { console.log('main'); }
    " 2>/dev/null || echo "main")
    PM=$(node -e "
        try {
            const c = JSON.parse(require('fs').readFileSync('sandcastle.config.json','utf8'));
            console.log(c.packageManager || 'pnpm');
        } catch { console.log('pnpm'); }
    " 2>/dev/null || echo "pnpm")
fi

for tmpl in "$TEMPLATES/workflows/"*.yml; do
    [[ ! -f "$tmpl" ]] && continue
    fname="$(basename "$tmpl")"
    vendored=".github/workflows/$fname"
    if [[ ! -f "$vendored" ]]; then
        DRIFTED_FILES+=("workflows/$fname (new — not installed)")
        DIFF_OUTPUT+="$(printf '\n── workflows/%s (new template) ──\n' "$fname")"
        continue
    fi
    # Resolve template variables for comparison
    resolved_tmpl=$(sed -e "s/{{DEFAULT_BRANCH}}/$BASE_BRANCH/g" -e "s/{{PACKAGE_MANAGER}}/$PM/g" "$tmpl")
    if ! echo "$resolved_tmpl" | diff -q "$vendored" - &>/dev/null; then
        DRIFTED_FILES+=("workflows/$fname")
        DIFF_OUTPUT+="$(printf '\n── workflows/%s ──\n' "$fname")"
        DIFF_OUTPUT+="$(echo "$resolved_tmpl" | diff -u "$vendored" - --label "installed/$fname" --label "template/$fname" 2>/dev/null || true)"
        DIFF_OUTPUT+=$'\n'
    fi
done

# 9. copilot-setup-steps.yml
echo "Checking copilot-setup-steps.yml..."
if [[ -f "$TEMPLATES/copilot-setup-steps.yml" ]] && [[ -f ".github/copilot-setup-steps.yml" ]]; then
    resolved_copilot=$(sed "s/{{PACKAGE_MANAGER}}/$PM/g" "$TEMPLATES/copilot-setup-steps.yml")
    if ! echo "$resolved_copilot" | diff -q ".github/copilot-setup-steps.yml" - &>/dev/null; then
        DRIFTED_FILES+=("copilot-setup-steps.yml")
        DIFF_OUTPUT+="$(printf '\n── copilot-setup-steps.yml ──\n')"
        DIFF_OUTPUT+="$(echo "$resolved_copilot" | diff -u ".github/copilot-setup-steps.yml" - --label "installed/copilot-setup-steps.yml" --label "template/copilot-setup-steps.yml" 2>/dev/null || true)"
        DIFF_OUTPUT+=$'\n'
    fi
fi

# ── Report ───────────────────────────────────────────────────────────────────
echo ""

if [[ ${#DRIFTED_FILES[@]} -eq 0 ]]; then
    green "No drift detected. Vendored files match dotfiles source."
    exit 0
fi

yellow "Drift detected in ${#DRIFTED_FILES[@]} file(s):"
echo ""
for f in "${DRIFTED_FILES[@]}"; do
    echo "  - $f"
done
echo ""

if [[ "$DRY_RUN" == true ]]; then
    echo "$DIFF_OUTPUT"
    echo ""
    yellow "Dry run — no changes made."
    exit 0
fi

# Show diffs
echo "$DIFF_OUTPUT"
echo ""

# ── Prompt for update ────────────────────────────────────────────────────────
echo "Options:"
echo "  [a] Update all drifted files"
echo "  [s] Update selectively (confirm each file)"
echo "  [q] Quit without changes"
echo ""
read -r -p "Choice [a/s/q]: " choice

case "$choice" in
    a|A)
        echo ""
        echo "Updating all..."
        ;;
    s|S)
        echo ""
        echo "Selective update..."
        ;;
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

apply_resolved() {
    local content="$1" dst="$2" label="$3"

    if [[ "$choice" == "s" || "$choice" == "S" ]]; then
        read -r -p "  Update $label? [y/n]: " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "    Skipped: $label"
            return
        fi
    fi

    mkdir -p "$(dirname "$dst")"
    echo "$content" > "$dst"
    echo "    Updated: $label"
    ((updated++)) || true
}

apply_dir_files() {
    local src_dir="$1" dst_dir="$2" label_prefix="$3"

    [[ -d "$src_dir" ]] || return
    for src_file in "$src_dir"/*; do
        [[ -f "$src_file" ]] || continue
        local fname dst
        fname="$(basename "$src_file")"
        dst="$dst_dir/$fname"
        if [[ ! -f "$dst" ]] || ! diff -q "$src_file" "$dst" &>/dev/null; then
            apply_file "$src_file" "$dst" "$label_prefix/$fname"
        fi
    done
}

# Re-run checks and apply (simpler than tracking which files drifted)

# Engine lib
for src_file in "$ENGINE/lib/"*.ts; do
    fname="$(basename "$src_file")"
    [[ "$fname" == *.test.ts ]] && continue
    dst=".sandcastle/engine/lib/$fname"
    if [[ ! -f "$dst" ]] || ! diff -q "$src_file" "$dst" &>/dev/null; then
        apply_file "$src_file" "$dst" "engine/lib/$fname"
    fi
done

# Engine schemas
for src_file in "$ENGINE/schemas/"*.ts; do
    [[ ! -f "$src_file" ]] && continue
    fname="$(basename "$src_file")"
    dst=".sandcastle/engine/schemas/$fname"
    if [[ ! -f "$dst" ]] || ! diff -q "$src_file" "$dst" &>/dev/null; then
        apply_file "$src_file" "$dst" "engine/schemas/$fname"
    fi
done

# Engine workflows
for src_file in "$ENGINE/workflows/"*.ts; do
    [[ ! -f "$src_file" ]] && continue
    fname="$(basename "$src_file")"
    [[ "$fname" == *.test.ts ]] && continue
    dst=".sandcastle/engine/workflows/$fname"
    if [[ ! -f "$dst" ]] || ! diff -q "$src_file" "$dst" &>/dev/null; then
        apply_file "$src_file" "$dst" "engine/workflows/$fname"
    fi
done

# Engine config files
if [[ ! -f ".sandcastle/engine/package.json" ]] || ! diff -q "$VENDORED_ENGINE_PACKAGE_JSON" ".sandcastle/engine/package.json" &>/dev/null; then
    apply_file "$VENDORED_ENGINE_PACKAGE_JSON" ".sandcastle/engine/package.json" "engine/package.json"
fi
for cfg in pnpm-lock.yaml tsconfig.json; do
    if [[ -f "$ENGINE/$cfg" ]]; then
        dst=".sandcastle/engine/$cfg"
        if [[ ! -f "$dst" ]] || ! diff -q "$ENGINE/$cfg" "$dst" &>/dev/null; then
            apply_file "$ENGINE/$cfg" "$dst" "engine/$cfg"
        fi
    fi
done

# Runtime prompt and extraction templates
apply_dir_files "$TEMPLATES/prompts" ".sandcastle/templates/prompts" "templates/prompts"
apply_dir_files "$TEMPLATES/extractions" ".sandcastle/templates/extractions" "templates/extractions"

# Helper scripts and hooks
apply_dir_files "$TEMPLATES/scripts" ".sandcastle/scripts" "scripts"
apply_dir_files "$TEMPLATES/hooks" ".sandcastle/hooks" "hooks"
chmod +x .sandcastle/scripts/*.sh .sandcastle/hooks/*.sh 2>/dev/null || true

# Optional sandbox template
if [[ "$SANDBOX" == "docker" || -d ".sandcastle/sandbox" ]]; then
    apply_dir_files "$TEMPLATES/sandbox" ".sandcastle/sandbox" "sandbox"
fi

# Workflow YAMLs
for tmpl in "$TEMPLATES/workflows/"*.yml; do
    [[ ! -f "$tmpl" ]] && continue
    fname="$(basename "$tmpl")"
    dst=".github/workflows/$fname"
    resolved=$(sed -e "s/{{DEFAULT_BRANCH}}/$BASE_BRANCH/g" -e "s/{{PACKAGE_MANAGER}}/$PM/g" "$tmpl")
    if [[ ! -f "$dst" ]] || ! echo "$resolved" | diff -q "$dst" - &>/dev/null; then
        apply_resolved "$resolved" "$dst" "workflows/$fname"
    fi
done

# copilot-setup-steps.yml
if [[ -f "$TEMPLATES/copilot-setup-steps.yml" ]]; then
    dst=".github/copilot-setup-steps.yml"
    resolved=$(sed "s/{{PACKAGE_MANAGER}}/$PM/g" "$TEMPLATES/copilot-setup-steps.yml")
    if [[ ! -f "$dst" ]] || ! echo "$resolved" | diff -q "$dst" - &>/dev/null; then
        apply_resolved "$resolved" "$dst" "copilot-setup-steps.yml"
    fi
fi

echo ""
green "Updated $updated file(s)."
