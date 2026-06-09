#!/usr/bin/env bash
# init-sandcastle.sh — Scaffold a complete Sandcastle setup in any repo.
#
# Usage: ctrl init-sandcastle [--branch main] [--model claude-opus-4-6] [--pm pnpm] [--sandbox none] [--force]
#
# Copies workflow YAMLs, vendors engine code, creates config, sets up prompt
# directory, creates GitHub labels, and prints a checklist of manual steps.

set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
source "$DOTFILES/bin/_lib.sh"

# ── Defaults ──────────────────────────────────────────────────────────────────
BRANCH="main"
MODEL="claude-opus-4-6"
PM="pnpm"
SANDBOX="none"
FORCE=false

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --branch)  BRANCH="$2"; shift 2 ;;
        --model)   MODEL="$2"; shift 2 ;;
        --pm)      PM="$2"; shift 2 ;;
        --sandbox) SANDBOX="$2"; shift 2 ;;
        --force)   FORCE=true; shift ;;
        --help|-h)
            echo "Usage: ctrl init-sandcastle [--branch main] [--model claude-opus-4-6] [--pm pnpm] [--sandbox none] [--force]"
            echo ""
            echo "Sandbox modes: only 'none' is currently supported by the TypeScript engine."
            exit 0
            ;;
        *) red "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Validate PM ───────────────────────────────────────────────────────────────
case "$PM" in
    npm|pnpm|yarn|bun) ;;
    *) red "Invalid package manager: $PM (must be npm, pnpm, yarn, or bun)"; exit 1 ;;
esac

# ── Validate sandbox ─────────────────────────────────────────────────────────
case "$SANDBOX" in
    none) ;;
    docker|worktree) red "Unsupported sandbox: $SANDBOX. Only 'none' is currently supported; Docker/worktree are not wired into the TypeScript engine yet."; exit 1 ;;
    *) red "Invalid sandbox: $SANDBOX (must be none)"; exit 1 ;;
esac

# ── Verify git repo ──────────────────────────────────────────────────────────
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    red "Not inside a git repository. Run this from a repo root."
    exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# ── Check existing install ────────────────────────────────────────────────────
if [[ -d ".sandcastle" ]] && [[ "$FORCE" != true ]]; then
    red ".sandcastle/ already exists. Use --force to overwrite (preserves prompts and config)."
    exit 1
fi

# ── Source paths ──────────────────────────────────────────────────────────────
TEMPLATES="$DOTFILES/shft/templates"
ENGINE="$DOTFILES/shft/engine"

if [[ ! -d "$TEMPLATES" ]]; then
    red "Templates not found at $TEMPLATES"
    exit 1
fi
if [[ ! -d "$ENGINE" ]]; then
    red "Engine not found at $ENGINE"
    exit 1
fi

green "Initializing Sandcastle in $(basename "$REPO_ROOT")..."
echo ""

# ── 1. Create directories ────────────────────────────────────────────────────
mkdir -p .github/workflows
mkdir -p .sandcastle/prompts

# ── 2. Copy workflow YAML templates ──────────────────────────────────────────
echo "  Installing workflow YAMLs..."
for tmpl in "$TEMPLATES/workflows/"*.yml; do
    fname="$(basename "$tmpl")"
    sed -e "s/{{DEFAULT_BRANCH}}/$BRANCH/g" -e "s/{{PACKAGE_MANAGER}}/$PM/g" "$tmpl" > ".github/workflows/$fname"
    echo "    .github/workflows/$fname"
done

# ── 3. Copy copilot-setup-steps.yml ──────────────────────────────────────────
echo "  Installing copilot-setup-steps.yml..."
sed "s/{{PACKAGE_MANAGER}}/$PM/g" "$TEMPLATES/copilot-setup-steps.yml" \
    > ".github/copilot-setup-steps.yml"
echo "    .github/copilot-setup-steps.yml"

# ── 4. Vendor engine code ────────────────────────────────────────────────────
echo "  Vendoring engine code..."
# Remove old vendored engine (but not prompts/config)
rm -rf .sandcastle/engine

# Copy engine, excluding node_modules and tests
mkdir -p .sandcastle/engine
cp "$ENGINE/package.json" .sandcastle/engine/
cp "$ENGINE/tsconfig.json" .sandcastle/engine/
[[ -f "$ENGINE/pnpm-lock.yaml" ]] && cp "$ENGINE/pnpm-lock.yaml" .sandcastle/engine/

mkdir -p .sandcastle/engine/lib
for f in "$ENGINE/lib/"*.ts; do
    fname="$(basename "$f")"
    # Skip test files
    [[ "$fname" == *.test.ts ]] && continue
    cp "$f" ".sandcastle/engine/lib/$fname"
done

mkdir -p .sandcastle/engine/schemas
cp "$ENGINE/schemas/"*.ts .sandcastle/engine/schemas/ 2>/dev/null || true

mkdir -p .sandcastle/engine/workflows
for f in "$ENGINE/workflows/"*.ts; do
    [[ -f "$f" ]] || continue
    fname="$(basename "$f")"
    [[ "$fname" == *.test.ts ]] && continue
    cp "$f" ".sandcastle/engine/workflows/$fname"
done

echo "    .sandcastle/engine/ (vendored)"

# ── 5. Create run.ts dispatcher ──────────────────────────────────────────────
echo "  Creating dispatcher..."
cp "$TEMPLATES/run.ts" .sandcastle/run.ts
echo "    .sandcastle/run.ts"

# ── 6. Copy runtime templates ────────────────────────────────────────────────
echo "  Installing runtime templates..."
mkdir -p .sandcastle/templates
rm -rf .sandcastle/templates/prompts .sandcastle/templates/extractions
cp -R "$TEMPLATES/prompts" .sandcastle/templates/
cp -R "$TEMPLATES/extractions" .sandcastle/templates/
echo "    .sandcastle/templates/prompts/"
echo "    .sandcastle/templates/extractions/"

# ── 7. Copy helper scripts and hooks ─────────────────────────────────────────
echo "  Installing helper scripts and hooks..."
rm -rf .sandcastle/scripts .sandcastle/hooks
cp -R "$TEMPLATES/scripts" .sandcastle/scripts
cp -R "$TEMPLATES/hooks" .sandcastle/hooks
chmod +x .sandcastle/scripts/*.sh .sandcastle/hooks/*.sh 2>/dev/null || true
echo "    .sandcastle/scripts/"
echo "    .sandcastle/hooks/"

# ── 8. Create config (only if not exists or --force without existing) ────────
if [[ ! -f "sandcastle.config.json" ]]; then
    echo "  Creating config..."
    cat > sandcastle.config.json <<CONFIGEOF
{
  "model": "$MODEL",
  "baseBranch": "$BRANCH",
  "sandbox": "$SANDBOX",
  "promptDir": ".sandcastle/prompts",
  "codingStandards": ".sandcastle/CODING_STANDARDS.md",
  "contextDoc": "CONTEXT.md",
  "adrDir": "docs/adr",
  "packageManager": "$PM"
}
CONFIGEOF
    echo "    sandcastle.config.json"
else
    yellow "  sandcastle.config.json already exists — skipping"
fi

# ── 9. Create CODING_STANDARDS.md skeleton ───────────────────────────────────
if [[ ! -f ".sandcastle/CODING_STANDARDS.md" ]]; then
    echo "  Creating CODING_STANDARDS.md skeleton..."
    cat > .sandcastle/CODING_STANDARDS.md <<'CSEOF'
# Coding Standards

<!-- Project-specific coding standards for Sandcastle agents. -->
<!-- Add your conventions, patterns, and constraints here. -->

## General

- Follow existing patterns in the codebase
- Write tests for new functionality
- Keep commits atomic and well-described

## Architecture

<!-- Document key architectural decisions and patterns here -->

## Testing

<!-- Document testing conventions here -->
CSEOF
    echo "    .sandcastle/CODING_STANDARDS.md"
else
    yellow "  .sandcastle/CODING_STANDARDS.md already exists — skipping"
fi

# ── 10. Create GitHub labels ─────────────────────────────────────────────────
echo "  Creating GitHub labels..."
if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
    LABELS_FILE="$TEMPLATES/labels.json"
    if [[ -f "$LABELS_FILE" ]]; then
        if command -v node &>/dev/null; then
            LABELS_FILE="$LABELS_FILE" node -e "
                const labels = JSON.parse(require('fs').readFileSync(process.env.LABELS_FILE, 'utf8'));
                labels.forEach(l => console.log(l.name + '|' + l.color + '|' + l.description));
            " | while IFS='|' read -r name color desc; do
                if gh label create "$name" --color "$color" --description "$desc" 2>/dev/null; then
                    echo "    Created: $name"
                else
                    echo "    Exists:  $name"
                fi
            done
        else
            yellow "    Node.js not found — skipping label creation. Create manually."
        fi
    fi
else
    yellow "    gh CLI not authenticated — skipping label creation"
    echo "    Run manually: gh label create <name> --color <hex> --description <desc>"
fi

# ── 11. Install engine dependencies ──────────────────────────────────────────
echo "  Installing engine dependencies..."
case "$PM" in
    pnpm) (cd .sandcastle/engine && pnpm install --ignore-scripts 2>/dev/null) || yellow "    pnpm install failed — run manually in .sandcastle/engine/" ;;
    yarn) (cd .sandcastle/engine && yarn install --ignore-scripts 2>/dev/null) || yellow "    yarn install failed — run manually in .sandcastle/engine/" ;;
    bun)  (cd .sandcastle/engine && bun install --ignore-scripts 2>/dev/null) || yellow "    bun install failed — run manually in .sandcastle/engine/" ;;
    npm)  (cd .sandcastle/engine && npm install --ignore-scripts 2>/dev/null) || yellow "    npm install failed — run manually in .sandcastle/engine/" ;;
    *)    red "Unexpected package manager after validation: $PM"; exit 1 ;;
esac

echo ""
green "Sandcastle initialized!"
echo ""

# ── Checklist ─────────────────────────────────────────────────────────────────
echo "  Next steps:"
echo "  ─────────────────────────────────────────────────────────"
echo "  1. Add repo secret: CLAUDE_CODE_OAUTH_TOKEN"
echo "     (GitHub → Settings → Secrets → Actions)"
echo ""
echo "  2. Add repo secret: ANTHROPIC_API_KEY"
echo "     (Required by workflows that call the Anthropic API directly.)"
echo ""
echo "  3. (Optional) Add repo secret: AGENT_PAT"
echo "     Needed for label changes to trigger downstream workflows."
echo "     Without it, the agent:implement → agent:review chain won't fire."
echo ""
echo "  4. Review sandcastle.config.json and adjust values"
echo ""
echo "  5. Add project-specific prompt overrides in .sandcastle/prompts/"
echo ""
echo "  6. Update .sandcastle/CODING_STANDARDS.md with your conventions"
echo ""
echo "  7. Create a CONTEXT.md at the repo root (optional but recommended)"
echo ""
echo "  8. Commit the generated files:"
echo "     git add .github/workflows/agent-*.yml .github/copilot-setup-steps.yml"
echo "     git add .sandcastle/ sandcastle.config.json"
echo "     git commit -m 'feat: initialize Sandcastle agent platform'"
echo ""
