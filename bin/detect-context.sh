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

# --- Expo / React Native ---
if [[ -f "package.json" ]] && grep -q '"expo"' package.json 2>/dev/null; then
    contexts="$contexts,expo"
fi
if [[ -f "package.json" ]] && grep -q '"react-native"' package.json 2>/dev/null; then
    contexts="$contexts,react-native"
fi
# Detect Expo inside a monorepo (apps/mobile has expo or app.config.ts exists)
if [[ -f "apps/mobile/package.json" ]] && grep -q '"expo"' apps/mobile/package.json 2>/dev/null; then
    contexts="$contexts,expo"
fi
if [[ -f "apps/mobile/app.config.ts" ]] || [[ -f "apps/mobile/app.config.js" ]]; then
    if [[ "$contexts" != *"expo"* ]]; then
        contexts="$contexts,expo"
    fi
fi
if compgen -G "metro.config.*" > /dev/null; then
    if [[ "$contexts" != *"react-native"* ]]; then
        contexts="$contexts,react-native"
    fi
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

# --- Better Auth ---
_dc_has_better_auth=false
while IFS= read -r _dc_pkg; do
    if grep -qE '"better-auth"[[:space:]]*:' "$_dc_pkg" 2>/dev/null; then
        _dc_has_better_auth=true
        break
    fi
done < <(find . -maxdepth 4 \
    \( -path './node_modules' -o -path './.git' -o -path './dist' -o -path './build' -o -path './.next' \) -prune -o \
    -name package.json -type f -print 2>/dev/null)

if [[ "$_dc_has_better_auth" != true ]]; then
    while IFS= read -r _dc_auth_file; do
        if grep -q 'better-auth' "$_dc_auth_file" 2>/dev/null; then
            _dc_has_better_auth=true
            break
        fi
    done < <(find . -maxdepth 5 \
        \( -path './node_modules' -o -path './.git' -o -path './dist' -o -path './build' -o -path './.next' \) -prune -o \
        -type f \( -name 'auth.ts' -o -name 'auth.tsx' -o -name 'auth.js' -o -name 'auth.jsx' -o -name 'auth-client.ts' -o -name 'auth-client.js' \) -print 2>/dev/null)
fi

if [[ "$_dc_has_better_auth" == true ]]; then
    contexts="$contexts,better-auth"
fi
unset _dc_has_better_auth _dc_pkg _dc_auth_file

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

# --- cmd (business operating system) ---
# Detects when working inside the cmd repo. Triggers cmd.instructions.md autoload.
_dc_cmd_dir="${CMD_DIR:-$HOME/cmd}"
# Expand ~ if present
_dc_cmd_dir="${_dc_cmd_dir/#\~/$HOME}"
_dc_cmd_dir="${_dc_cmd_dir%/}"
if [[ -n "$_dc_cmd_dir" ]] && { [[ "$PWD" == "$_dc_cmd_dir" ]] || [[ "$PWD" == "$_dc_cmd_dir"/* ]]; } && [[ -f "$_dc_cmd_dir/CLAUDE.md" ]]; then
    contexts="$contexts,cmd"
fi
unset _dc_cmd_dir

export ACTIVE_CONTEXTS="$contexts"
echo "$contexts"

# ── HUD context event (inline, non-blocking, never fails) ───────────────
# Pushes a context-change event to the HUD daemon on every cd().
# Inline push avoids subprocess overhead — this runs on every directory change.
{
    _dc_dotfiles="${DOTFILES:-$HOME/dotfiles}"
    _dc_pipe="$_dc_dotfiles/working/runtime/hud.pipe"
    _dc_events="$_dc_dotfiles/working/logs/events.jsonl"
    _dc_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")
    _dc_td=$(date +"%H:%M:%S" 2>/dev/null || echo "")
    _dc_proj=$(basename "$(pwd)" 2>/dev/null || echo "unknown")

    # Detect IDE from environment
    _dc_ide="terminal"
    if [[ -n "${VSCODE_PID:-}" ]] || [[ -n "${VSCODE_IPC_HOOK:-}" ]]; then
        _dc_ide="vscode"
    elif [[ -n "${CURSOR_SESSION_ID:-}" ]]; then
        _dc_ide="cursor"
    fi

    _dc_payload=$(printf '{"type":"context","project":"%s","projectPath":"%s","contexts":"%s","ide":"%s","message":"Active contexts: %s","timestamp":"%s","time":"%s"}' \
        "$_dc_proj" "${PWD/$HOME/~}" "$contexts" "$_dc_ide" "$contexts" "$_dc_ts" "$_dc_td")

    if [[ -p "$_dc_pipe" ]] && [[ "$(uname -o 2>/dev/null)" != "Msys" ]]; then
        ( printf '%s\n' "$_dc_payload" > "$_dc_pipe" ) 2>/dev/null &
        disown 2>/dev/null
    else
        mkdir -p "$_dc_dotfiles/working/logs" 2>/dev/null || true
        printf '%s\n' "$_dc_payload" >> "$_dc_events" 2>/dev/null &
        disown 2>/dev/null
    fi
    unset _dc_dotfiles _dc_pipe _dc_events _dc_ts _dc_td _dc_proj _dc_ide _dc_payload
} 2>/dev/null || true
