#!/usr/bin/env bash
# init-sandcastle.sh — Scaffold a complete Sandcastle setup in any repo.
#
# Usage: ctrl init-sandcastle [--branch main] [--model claude-opus-4-7] [--sandbox none] [--no-proxy] [--with-proxy-canary] [--force]
#
# Installs thin workflow stubs that reference the Sandcastle hub engine remotely
# (uses: arndvs/ctrlshft-hub/actions/agent-run@<ref>), writes a hub-version pin,
# creates config, sets up prompt directory, creates GitHub labels, and prints a
# checklist of manual steps. The engine is NOT vendored — it lives in the hub.

set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
source "$DOTFILES/bin/_lib.sh"

# Producer source of truth for Sandcastle templates. Defaults to the ctrlshft-public
# checkout (the durable public product home); falls back to dotfiles-private if not
# present. Override with SANDBOX_PRODUCER=/path/to/producer.
SANDBOX_PRODUCER="${SANDBOX_PRODUCER:-$HOME/dev/clients/ctrlshft-public}"
if [[ ! -d "$SANDBOX_PRODUCER/shft" ]]; then
    SANDBOX_PRODUCER="$DOTFILES"
fi

# ── Defaults ──────────────────────────────────────────────────────────────────
BRANCH="main"
MODEL="claude-opus-4-7"
SANDBOX="none"
FORCE=false
NO_ARTIFACTS=false
WITH_PROXY=true
WITH_PROXY_CANARY=false

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --branch)  BRANCH="$2"; shift 2 ;;
        --model)   MODEL="$2"; shift 2 ;;
        --sandbox) SANDBOX="$2"; shift 2 ;;
        --with-proxy) WITH_PROXY=true; shift ;;
        --no-proxy)   WITH_PROXY=false; shift ;;
        --with-proxy-canary) WITH_PROXY_CANARY=true; shift ;;
        --no-proxy-canary)   WITH_PROXY_CANARY=false; shift ;;
        --force)   FORCE=true; shift ;;
        --no-artifacts) NO_ARTIFACTS=true; shift ;;
        --help|-h)
            echo "Usage: ctrl init-sandcastle [--branch main] [--model claude-opus-4-7] [--sandbox none] [--no-proxy] [--with-proxy-canary] [--no-artifacts] [--force]"
            echo ""
            echo "Also scaffolds the artifact lifecycle (working/, plans/, docs/) by calling"
            echo "'ctrl init-artifacts --gitignore'. Pass --no-artifacts to skip it."
            echo ""
            echo "Proxy: agents route through a LiteLLM->Copilot proxy by default (--with-proxy)."
            echo "Pass --no-proxy to disable proxy routing (records proxy=false in"
            echo "sandcastle.config.json) and use ANTHROPIC_API_KEY instead of LITELLM_*."
            echo ""
            echo "Proxy canary: the scheduled proxy-canary.yml monitor is NOT installed by"
            echo "default. Pass --with-proxy-canary to opt in (records proxyCanary=true)."
            echo "Pass --no-proxy-canary to explicitly disable (the default)."
            echo ""
            echo "Sandbox modes: only 'none' is currently supported by the TypeScript engine."
            exit 0
            ;;
        *) red "Unknown option: $1"; exit 1 ;;
    esac
done


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
TEMPLATES="$SANDBOX_PRODUCER/shft/templates"

if [[ ! -d "$TEMPLATES" ]]; then
    red "Templates not found at $TEMPLATES"
    exit 1
fi

# Hub reference for the engine. Consumers reference the hub action remotely;
# the engine is never vendored. Override with SANDBOX_HUB_REF (branch/tag/SHA).
SANDBOX_HUB_REF="${SANDBOX_HUB_REF:-main}"
SANDBOX_HUB_ACTION="arndvs/ctrlshft-hub/actions/agent-run@${SANDBOX_HUB_REF}"

# Render a workflow template with variable + auth-mode substitution.
# Proxy mode (default): keeps LITELLM_* env vars (routes through the proxy).
# No-proxy mode:        replaces them with a direct ANTHROPIC_API_KEY secret.
render_workflow() {
    local tmpl="$1"
    if [[ "$WITH_PROXY" == false ]]; then
        sed -e "s/{{DEFAULT_BRANCH}}/$BRANCH/g" \
            -e '/ANTHROPIC_BASE_URL:.*LITELLM_BASE_URL/d' \
            -e '/ANTHROPIC_AUTH_TOKEN:.*LITELLM_MASTER_KEY/d' \
            "$tmpl"
    else
        sed -e "s/{{DEFAULT_BRANCH}}/$BRANCH/g" "$tmpl"
    fi
}

green "Initializing Sandcastle in $(basename "$REPO_ROOT")..."
echo ""

# ── 1. Create directories ────────────────────────────────────────────────────
mkdir -p .github/workflows
mkdir -p .sandcastle/prompts

# ── 2. Install thin workflow stubs (hub model) ───────────────────────────────
# Each stub references the hub action remotely. The engine is never vendored.
echo "  Installing workflow stubs (hub model)..."
for tmpl in "$TEMPLATES/workflows/"*.yml; do
    fname="$(basename "$tmpl")"
    render_workflow "$tmpl" > ".github/workflows/$fname"
    echo "    .github/workflows/$fname"
done

# ── 3. Copy copilot-setup-steps.yml ──────────────────────────────────────────
echo "  Installing copilot-setup-steps.yml..."
cp "$TEMPLATES/copilot-setup-steps.yml" ".github/copilot-setup-steps.yml"
echo "    .github/copilot-setup-steps.yml"

# ── 3b. Copy proxy monitoring workflows (only with --with-proxy-canary) ──────
if [[ "$WITH_PROXY_CANARY" == true ]]; then
    echo "  Installing proxy monitoring workflows..."
    for tmpl in "$TEMPLATES/workflows-proxy/"*.yml; do
        [[ -f "$tmpl" ]] || continue
        fname="$(basename "$tmpl")"
        render_workflow "$tmpl" > ".github/workflows/$fname"
        echo "    .github/workflows/$fname"
    done
else
    yellow "  Skipping proxy monitoring workflows (proxyCanary=false; pass --with-proxy-canary to install)"
fi

# ── 4. Write hub-version pin (provenance + staleness detection) ──────────────
# Consumers pin the hub ref they run from. The sandcastle-drift workflow compares
# this to the hub's latest main and opens a review PR when stale.
echo "  Writing hub-version pin..."
cat > .sandcastle/hub-version.json <<HUBEOF
{
  "ref": "${SANDBOX_HUB_REF}",
  "lastPinnedSha": "unknown",
  "reviewedAt": "$(date -u +%Y-%m-%d)"
}
HUBEOF
echo "    .sandcastle/hub-version.json (ref: $SANDBOX_HUB_REF)"

# ── 5. Copy runtime templates (prompts + extractions) ────────────────────────
echo "  Installing runtime templates..."
mkdir -p .sandcastle/templates
rm -rf .sandcastle/templates/prompts .sandcastle/templates/extractions
cp -R "$TEMPLATES/prompts" .sandcastle/templates/
cp -R "$TEMPLATES/extractions" .sandcastle/templates/
echo "    .sandcastle/templates/prompts/"
echo "    .sandcastle/templates/extractions/"

# Vendor the label definitions so labels-sync.yml can reconcile from a local source.
cp "$TEMPLATES/labels.json" .sandcastle/labels.json
echo "    .sandcastle/labels.json"

# ── 6. Create config (only if not exists or --force without existing) ────────
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
  "packageManager": "pnpm",
  "proxy": $WITH_PROXY,
  "proxyCanary": $WITH_PROXY_CANARY
}
CONFIGEOF
    echo "    sandcastle.config.json"
else
    yellow "  sandcastle.config.json already exists — skipping"
fi

# ── 7. Create CODING_STANDARDS.md skeleton ───────────────────────────────────
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

# ── 8. Create GitHub labels ─────────────────────────────────────────────────
echo "  Creating GitHub labels..."
if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
    LABELS_FILE="$TEMPLATES/labels.json"
    if ! gh repo view &>/dev/null; then
        yellow "    gh CLI could not resolve a GitHub repository — skipping label creation"
        echo "    Run manually after adding a GitHub remote: gh label create <name> --color <hex> --description <desc>"
    elif [[ -f "$LABELS_FILE" ]]; then
        if command -v node &>/dev/null; then
            LABELS_FILE="$LABELS_FILE" node -e "
                const labels = JSON.parse(require('fs').readFileSync(process.env.LABELS_FILE, 'utf8'));
                labels.forEach(l => console.log(l.name + '|' + l.color + '|' + l.description));
            " | while IFS='|' read -r name color desc; do
                label_output="$(gh label create "$name" --color "$color" --description "$desc" 2>&1)" && label_status=0 || label_status=$?
                if [[ $label_status -eq 0 ]]; then
                    echo "    Created: $name"
                elif grep -qi "already exists" <<<"$label_output"; then
                    echo "    Exists:  $name"
                else
                    yellow "    Failed:  $name — $label_output"
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

# ── 9. Secrets preflight ─────────────────────────────────────────────────────
# Warn (never fail) if required Actions secrets are missing. Names only — gh never
# exposes secret values. A missing AGENT_PAT is the most common cause of "every issue
# lands in agent:blocked", so surface it now instead of at first workflow run.
echo "  Checking repo secrets..."
required_secrets=(AGENT_PAT)
if [[ "$WITH_PROXY" == true ]]; then
    required_secrets+=(LITELLM_BASE_URL LITELLM_MASTER_KEY)
else
    required_secrets+=(ANTHROPIC_API_KEY)
fi
# Resolve owner/repo from origin so this works regardless of how many remotes exist
# (gh's bare `secret list` errors when multiple remotes are present).
repo_slug="$(git remote get-url origin 2>/dev/null | sed -E 's#^(git@[^:]+:|https?://[^/]+/)##; s#\.git$##')"
if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1 && [[ -n "$repo_slug" ]] && gh repo view "$repo_slug" &>/dev/null 2>&1; then
    existing_secrets="$(gh secret list -R "$repo_slug" 2>/dev/null | awk 'NF {print $1}')"
    for secret in "${required_secrets[@]}"; do
        if grep -qx "$secret" <<<"$existing_secrets"; then
            echo "    Present: $secret"
        else
            yellow "    Missing: $secret — workflows needing it fail closed (issues land in agent:blocked)"
        fi
    done
else
    yellow "    Skipped secret check (gh not authenticated or no GitHub repo resolved)"
fi

# ── 10. Scaffold artifact lifecycle (additive; opt out with --no-artifacts) ──
# Delegates to the shared lifecycle scaffold rather than owning lifecycle files
# here, so Sandcastle does not become the owner of the lifecycle concept.
if [[ "$NO_ARTIFACTS" != true ]]; then
    echo "  Scaffolding artifact lifecycle..."
    if [[ -f "$DOTFILES/bin/init-artifacts.sh" ]]; then
        bash "$DOTFILES/bin/init-artifacts.sh" --gitignore \
            || yellow "    lifecycle scaffold reported issues — run 'ctrl init-artifacts' manually"
    else
        yellow "    init-artifacts.sh not found — skipping lifecycle scaffold"
    fi
else
    yellow "  Skipping artifact lifecycle scaffold (--no-artifacts)"
fi

echo ""
green "Sandcastle initialized!"
echo ""

# ── Checklist ─────────────────────────────────────────────────────────────────
echo "  Next steps:"
echo "  ─────────────────────────────────────────────────────────"
if [[ "$WITH_PROXY" == true ]]; then
    echo "  1. Add repo secrets: LITELLM_BASE_URL and LITELLM_MASTER_KEY"
    echo "     Required to route model traffic through the Claude-compatible LiteLLM proxy."
    echo "     (Or run: ctrl sandcastle-wire-secrets)"
else
    echo "  1. Add repo secret: ANTHROPIC_API_KEY"
    echo "     Direct Anthropic API key — no proxy required."
fi
echo ""
echo "  2. Add repo secret: AGENT_PAT  (the 'Checking repo secrets' step above flags it if missing)"
echo "     Required for label changes to trigger downstream workflows."
echo "     GITHUB_TOKEN-created labels do not fire follow-up workflow runs."
echo ""
echo ""
echo "  3. Review sandcastle.config.json and adjust values"
echo ""
echo "  4. Add project-specific prompt overrides in .sandcastle/prompts/"
echo ""
echo "  5. Update .sandcastle/CODING_STANDARDS.md with your conventions"
echo ""
echo "  6. Create a CONTEXT.md at the repo root (optional but recommended)"
echo ""
echo "  7. Review .sandcastle/hub-version.json — it pins the hub ref ($SANDBOX_HUB_REF)."
echo "     The sandcastle-drift workflow opens a review PR when the hub advances."
echo ""
echo "  8. Commit the generated files:"
echo "     git add .github/workflows/ .github/copilot-setup-steps.yml"
echo "     git add .sandcastle/ sandcastle.config.json"
echo "     git commit -m 'feat: initialize Sandcastle agent platform'"
echo ""
