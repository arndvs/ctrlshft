#!/usr/bin/env bash
# init-sandcastle.sh — Scaffold the Sandcastle framework into a target repository.
#
# Copies the engine, templates, workflows, and config into the target repo's
# .sandcastle/ and .github/ directories. Creates sandcastle.config.json and
# installs GitHub labels from labels.json.
#
# Usage:
#   bash bin/init-sandcastle.sh [TARGET_DIR] [--sandbox none|docker] [--help]
#
# If TARGET_DIR is omitted, defaults to the current working directory.
#
# Exit code: 0 on success, 1 on failure.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
SHFT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../shft" && pwd)"
TEMPLATES_DIR="$SHFT_DIR/templates"
ENGINE_DIR="$SHFT_DIR/engine"

# ── Defaults ─────────────────────────────────────────────────────────────────
TARGET_DIR=""
SANDBOX="none"

# ── Arg parsing ──────────────────────────────────────────────────────────────
for arg in "$@"; do
    case "$arg" in
        --sandbox)   :;; # value consumed below
        none|docker) :;; # consumed as --sandbox value
        --help|-h)
            echo ""
            echo "  init-sandcastle — Scaffold Sandcastle into a target repository"
            echo ""
            echo "  Usage: ctrl init-sandcastle [TARGET_DIR] [--sandbox none|docker]"
            echo ""
            echo "  Arguments:"
            echo "    TARGET_DIR          Path to the target repo (default: current directory)"
            echo "    --sandbox MODE      Sandbox mode: none (default) or docker"
            echo "    --help              Show this help message"
            echo ""
            echo "  What it does:"
            echo "    1. Creates .sandcastle/ with engine, prompts, extractions, scripts"
            echo "    2. Copies workflow templates to .github/workflows/"
            echo "    3. Copies copilot-setup-steps.yml to .github/"
            echo "    4. Generates sandcastle.config.json"
            echo "    5. Installs GitHub labels from labels.json"
            echo "    6. Replaces {{DEFAULT_BRANCH}} tokens with the repo's default branch"
            echo ""
            exit 0
            ;;
        *)  :;;
    esac
done

# Parse positional + flag args properly
_prev=""
for arg in "$@"; do
    if [[ "$_prev" == "--sandbox" ]]; then
        SANDBOX="$arg"
        _prev=""
        continue
    fi
    case "$arg" in
        --sandbox) _prev="--sandbox" ;;
        --help|-h) ;; # handled above
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
if [[ ! -d "$TARGET_DIR/.git" ]]; then
    red "  ✗ $TARGET_DIR is not a git repository"
    exit 1
fi

if [[ -d "$TARGET_DIR/.sandcastle" ]]; then
    red "  ✗ .sandcastle/ already exists in $TARGET_DIR"
    echo "  Use 'ctrl update-sandcastle' to update an existing installation."
    exit 1
fi

if [[ ! -d "$TEMPLATES_DIR" ]]; then
    red "  ✗ Templates directory not found: $TEMPLATES_DIR"
    exit 1
fi

if [[ ! -d "$ENGINE_DIR" ]]; then
    red "  ✗ Engine directory not found: $ENGINE_DIR"
    exit 1
fi

# ── Detect default branch ───────────────────────────────────────────────────
_default_branch=""
if git -C "$TARGET_DIR" symbolic-ref refs/remotes/origin/HEAD &>/dev/null; then
    _default_branch=$(git -C "$TARGET_DIR" symbolic-ref refs/remotes/origin/HEAD | sed 's|refs/remotes/origin/||')
fi

if [[ -z "$_default_branch" ]]; then
    # Fallback: check common branch names
    for branch in main master; do
        if git -C "$TARGET_DIR" show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
            _default_branch="$branch"
            break
        fi
    done
fi

if [[ -z "$_default_branch" ]]; then
    _default_branch="main"
    yellow "  ~ Could not detect default branch, using: $_default_branch"
fi

green "init-sandcastle — scaffolding into $TARGET_DIR"
echo ""
echo "  Default branch: $_default_branch"
echo "  Sandbox mode:   $SANDBOX"
echo ""

# ── Create .sandcastle/ structure ────────────────────────────────────────────
echo "Scaffolding .sandcastle/:"

_sc="$TARGET_DIR/.sandcastle"
mkdir -p "$_sc"

# Copy prompts
cp -r "$TEMPLATES_DIR/prompts" "$_sc/prompts"
green "  ✓ prompts/ ($(ls "$_sc/prompts" | wc -l | tr -d ' ') files)"

# Copy extractions
cp -r "$TEMPLATES_DIR/extractions" "$_sc/extractions"
green "  ✓ extractions/ ($(ls "$_sc/extractions" | wc -l | tr -d ' ') files)"

# Copy hooks
cp -r "$TEMPLATES_DIR/hooks" "$_sc/hooks"
green "  ✓ hooks/"

# Copy sandbox
cp -r "$TEMPLATES_DIR/sandbox" "$_sc/sandbox"
green "  ✓ sandbox/"

# Copy scripts
cp -r "$TEMPLATES_DIR/scripts" "$_sc/scripts"
green "  ✓ scripts/"

# Copy run.ts dispatcher
cp "$TEMPLATES_DIR/run.ts" "$_sc/run.ts"
green "  ✓ run.ts"

# Copy labels.json for future updates
cp "$TEMPLATES_DIR/labels.json" "$_sc/labels.json"
green "  ✓ labels.json"

# ── Vendor engine ────────────────────────────────────────────────────────────
echo ""
echo "Vendoring engine:"

_engine_dest="$_sc/node_modules/.sandcastle-engine"
mkdir -p "$_engine_dest"

# Copy engine source files (exclude node_modules, tests, dev config)
for item in main.ts lib schemas workflows prompts; do
    if [[ -d "$ENGINE_DIR/$item" ]]; then
        cp -r "$ENGINE_DIR/$item" "$_engine_dest/$item"
    elif [[ -f "$ENGINE_DIR/$item" ]]; then
        cp "$ENGINE_DIR/$item" "$_engine_dest/$item"
    fi
done

green "  ✓ Engine vendored to .sandcastle/node_modules/.sandcastle-engine/"

# ── Generate .sandcastle/package.json ────────────────────────────────────────
cat > "$_sc/package.json" << 'PKGJSON'
{
  "name": "sandcastle-local",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "dependencies": {
    "@ai-hero/sandcastle": "^0.5.11",
    "zod": "^3.24.0"
  },
  "devDependencies": {
    "tsx": "^4.19.0",
    "typescript": "^5.7.0"
  }
}
PKGJSON
green "  ✓ package.json"

# ── Generate tsconfig.json ───────────────────────────────────────────────────
cat > "$_sc/tsconfig.json" << 'TSCONFIG'
{
  "compilerOptions": {
    "target": "ES2024",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "outDir": "dist"
  },
  "include": ["run.ts", "node_modules/.sandcastle-engine/**/*.ts"]
}
TSCONFIG
green "  ✓ tsconfig.json"

# ── Copy GitHub workflows ────────────────────────────────────────────────────
echo ""
echo "Installing GitHub workflows:"

_wf_dir="$TARGET_DIR/.github/workflows"
mkdir -p "$_wf_dir"

_wf_count=0
for wf in "$TEMPLATES_DIR/workflows/"*.yml; do
    _name=$(basename "$wf")
    # Replace {{DEFAULT_BRANCH}} tokens
    sed "s/{{DEFAULT_BRANCH}}/$_default_branch/g" "$wf" > "$_wf_dir/$_name"
    _wf_count=$((_wf_count + 1))
done
green "  ✓ $_wf_count workflow files → .github/workflows/"

# ── Copy copilot-setup-steps.yml ─────────────────────────────────────────────
cp "$TEMPLATES_DIR/copilot-setup-steps.yml" "$TARGET_DIR/.github/copilot-setup-steps.yml"
green "  ✓ copilot-setup-steps.yml → .github/"

# ── Generate sandcastle.config.json ──────────────────────────────────────────
echo ""
echo "Generating config:"

_config_path="$TARGET_DIR/sandcastle.config.json"
cat > "$_config_path" << CONFIGJSON
{
  "defaultBranch": "$_default_branch",
  "model": "claude-sonnet-4-20250514",
  "maxIterations": 1,
  "maxParallel": 4,
  "maxIssues": 5,
  "sandbox": "$SANDBOX",
  "maxReviewRounds": 3,
  "scoreThresholds": {
    "auto": 75,
    "confirm": 40
  }
}
CONFIGJSON
green "  ✓ sandcastle.config.json"

# ── Install GitHub labels ────────────────────────────────────────────────────
echo ""
echo "Installing GitHub labels:"

if command -v gh &>/dev/null; then
    _label_count=0
    _label_skip=0

    # Parse labels.json and create each label
    while IFS= read -r label_line; do
        _lname=$(echo "$label_line" | cut -d'|' -f1)
        _ldesc=$(echo "$label_line" | cut -d'|' -f2)
        _lcolor=$(echo "$label_line" | cut -d'|' -f3)

        if gh label create "$_lname" --description "$_ldesc" --color "$_lcolor" --repo "$(git -C "$TARGET_DIR" remote get-url origin 2>/dev/null)" --force 2>/dev/null; then
            _label_count=$((_label_count + 1))
        else
            _label_skip=$((_label_skip + 1))
        fi
    done < <(python3 -c "
import json, sys
with open('$TEMPLATES_DIR/labels.json') as f:
    labels = json.load(f)
for l in labels:
    print(f\"{l['name']}|{l['description']}|{l['color']}\")
" 2>/dev/null || {
        # Fallback: parse with jq if available
        jq -r '.[] | "\(.name)|\(.description)|\(.color)"' "$TEMPLATES_DIR/labels.json" 2>/dev/null
    })

    if [[ $_label_count -gt 0 ]]; then
        green "  ✓ $_label_count labels created"
    fi
    if [[ $_label_skip -gt 0 ]]; then
        yellow "  ~ $_label_skip labels skipped (may already exist)"
    fi
else
    yellow "  ~ gh CLI not found — skipping label creation"
    echo "  Install: https://cli.github.com"
    echo "  Then run: ctrl init-sandcastle --labels-only"
fi

# ── Verify tokens ────────────────────────────────────────────────────────────
echo ""
echo "Verifying template tokens:"

if bash "$_sc/scripts/check-file-tokens.sh" "$_sc" 2>/dev/null && \
   bash "$_sc/scripts/check-file-tokens.sh" "$_wf_dir" 2>/dev/null; then
    green "  ✓ All template tokens replaced"
else
    yellow "  ~ Some tokens may need manual replacement"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
green "Sandcastle initialized successfully!"
echo ""
echo "  Next steps:"
echo "    1. cd $TARGET_DIR/.sandcastle && npm install"
echo "    2. Add ANTHROPIC_API_KEY to your GitHub repo secrets:"
echo "       bash .sandcastle/scripts/setup-github-secrets.sh"
echo "    3. Commit the scaffolded files"
echo "    4. Label an issue with 'agent:implement' to trigger the first agent run"
echo ""
