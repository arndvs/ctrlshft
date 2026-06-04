#!/bin/bash
set -eo pipefail

# ============================================================
# Sandcastle — GitHub Secrets Setup
# ============================================================
#
# Walks you through setting the secrets needed for agent
# workflows to authenticate with Anthropic and GitHub.
#
# Secrets configured:
#
#   1. ANTHROPIC_API_KEY
#      API key for Claude. Used by the engine to call the
#      Anthropic API from GitHub Actions runners.
#
#      Get one at: https://console.anthropic.com/settings/keys
#
#   2. AGENT_PAT  (optional but recommended)
#      A GitHub Personal Access Token (classic) with repo scope.
#      Used for label mutations that trigger downstream workflows
#      (GITHUB_TOKEN cannot trigger other workflow runs).
#
#      Create at: https://github.com/settings/tokens
#      Required scope: repo
#
# ============================================================

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)

if [[ -z "$REPO" ]]; then
  echo "Error: Could not determine repo. Make sure you're in a git repo with a GitHub remote."
  exit 1
fi

echo "Setting up secrets for: $REPO"
echo ""

set_secret() {
  local name="$1"
  local description="$2"
  local instructions="$3"

  echo "--- $name ---"
  echo ""
  echo "  $description"
  echo "  $instructions"
  echo ""

  local existing
  existing=$(gh secret list --repo "$REPO" 2>/dev/null | grep "$name" || true)
  if [[ -n "$existing" ]]; then
    echo "  [Already set] $name exists. Overwrite? (y/N)"
    read -r overwrite
    if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
      echo "  Skipping."
      echo ""
      return
    fi
  fi

  echo "  Paste your $name (input is hidden):"
  read -rs token
  echo "$token" | gh secret set "$name" --repo "$REPO"
  echo "  Set."
  echo ""
}

set_secret "ANTHROPIC_API_KEY" \
  "API key for Claude (Anthropic)." \
  "Get one at: https://console.anthropic.com/settings/keys"

set_secret "AGENT_PAT" \
  "GitHub PAT (classic) with repo scope." \
  "Create at: https://github.com/settings/tokens — scope: repo"

# --- Verify ---

echo "============================================================"
echo "Secrets configured for $REPO:"
echo ""
gh secret list --repo "$REPO"
echo ""
echo "============================================================"
