#!/usr/bin/env bash
# detect-context.sh — Detect workspace project type from file signatures.
#
# Run from any project directory. Outputs a comma-separated context string
# and exports it as ACTIVE_CONTEXTS for the current shell.
#
# Usage:
#   source ~/dotfiles/bin/detect-context.sh          # from shell / .envrc
#   export ACTIVE_CONTEXTS=$(~/dotfiles/bin/detect-context.sh)  # one-liner
#
# Copilot / Claude agents read ACTIVE_CONTEXTS to decide which skills to load.
# Skills declare their relevant contexts in frontmatter: contexts: [nextjs, prisma]
# Skills with contexts: [general] (or no contexts field) always load.

# Guard: when sourced into an interactive shell, save and restore shell options
# so set -euo pipefail doesn't bleed into the parent session.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    _dc_oldopts=$(set +o)
    trap 'eval "$_dc_oldopts"; unset _dc_oldopts' RETURN
fi
set -euo pipefail

contexts="general"

# --- Next.js ---
if [[ -f "next.config.ts" ]] || [[ -f "next.config.js" ]] || [[ -f "next.config.mjs" ]] || [[ -f "next.config.mts" ]]; then
    contexts="$contexts,nextjs"
fi

# --- React Native ---
if [[ -f "package.json" ]] && grep -q '"react-native"' package.json 2>/dev/null; then
    contexts="$contexts,react-native"
fi

# --- React (non-Next, non-Native) ---
# Must come AFTER react-native check — both match "react" in package.json
if [[ -f "package.json" ]] && grep -qE '"react"\s*:' package.json 2>/dev/null; then
    if [[ "$contexts" != *"nextjs"* && "$contexts" != *"react-native"* ]]; then
        contexts="$contexts,react"
    fi
fi

# --- Node / TypeScript ---
if [[ -f "package.json" ]]; then
    contexts="$contexts,node"
fi
if [[ -f "tsconfig.json" ]]; then
    contexts="$contexts,typescript"
fi

# --- PHP ---
if [[ -f "composer.json" ]]; then
    contexts="$contexts,php"
fi

# --- Sanity CMS ---
if [[ -f "sanity.config.ts" ]] || [[ -f "sanity.config.js" ]] || [[ -f "sanity.config.mjs" ]] || [[ -f "sanity.config.mts" ]] || [[ -f "sanity.cli.ts" ]] || [[ -f "sanity.cli.js" ]]; then
    contexts="$contexts,sanity"
fi

# --- Prisma ---
if [[ -f "prisma/schema.prisma" ]]; then
    contexts="$contexts,prisma"
fi

# --- Docker ---
if [[ -f "Dockerfile" ]] || [[ -f "docker-compose.yml" ]] || [[ -f "docker-compose.yaml" ]] || [[ -f "compose.yaml" ]] || [[ -f "compose.yml" ]]; then
    contexts="$contexts,docker"
fi

# --- Python ---
if [[ -f "requirements.txt" ]] || [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]] || [[ -f "Pipfile" ]]; then
    contexts="$contexts,python"
fi

# --- Laravel ---
if [[ -f "artisan" ]]; then
    contexts="$contexts,laravel"
fi

export ACTIVE_CONTEXTS="$contexts"
echo "$contexts"
