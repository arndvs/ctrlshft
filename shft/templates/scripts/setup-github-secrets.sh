#!/usr/bin/env bash
# setup-github-secrets.sh — Configure required GitHub Actions secrets
#
# Prompts for and sets the secrets needed by Sandcastle agent workflows.
# Requires `gh` CLI authenticated with admin access to the target repo.

set -euo pipefail

REPO="${1:-}"

if [ -z "$REPO" ]; then
  # Try to detect from git remote
  REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || true)
  if [ -z "$REPO" ]; then
    echo "Usage: setup-github-secrets.sh <owner/repo>" >&2
    exit 1
  fi
fi

echo "Setting up Sandcastle secrets for $REPO"
echo ""

# ANTHROPIC_API_KEY
echo "1. ANTHROPIC_API_KEY"
echo "   Required for all agent workflows. Get one at https://console.anthropic.com/"
read -rsp "   Enter your Anthropic API key (input hidden): " ANTHROPIC_KEY
echo ""

if [ -n "$ANTHROPIC_KEY" ]; then
  echo "$ANTHROPIC_KEY" | gh secret set ANTHROPIC_API_KEY --repo "$REPO"
  echo "   Set ANTHROPIC_API_KEY"
else
  echo "   Skipped (empty)"
fi

echo ""
echo "Setup complete. Verify with: gh secret list --repo $REPO"
echo ""
echo "Note: GITHUB_TOKEN is automatically provided by GitHub Actions."
echo "For additional permissions, configure a fine-grained PAT if needed."
