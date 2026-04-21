#!/usr/bin/env bash
# new-client.sh — Scaffold a new client in ~/dotfiles/clients/

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
CLIENTS_DIR="$DOTFILES/clients"
TEMPLATE_DIR="$CLIENTS_DIR/_template"

CLIENT_SLUG="${1:-}"
CLIENT_NAME="${2:-}"

if [[ -z "$CLIENT_SLUG" ]]; then
    echo ""
    echo "  New client setup"
    echo "  ─────────────────────────────────────────────────"
    echo ""
    read -rp "  Client slug (no spaces, e.g. alignsd): " CLIENT_SLUG
fi

if [[ ! "$CLIENT_SLUG" =~ ^[a-z0-9_-]+$ ]]; then
    red "Client slug must be lowercase letters, numbers, hyphens, or underscores"
    red "Got: $CLIENT_SLUG"
    exit 1
fi

if [[ -z "$CLIENT_NAME" ]]; then
    read -rp "  Client display name (e.g. AlignSD Wellness Center): " CLIENT_NAME
fi

CLIENT_DIR="$CLIENTS_DIR/$CLIENT_SLUG"

if [[ -d "$CLIENT_DIR" ]]; then
    yellow "Client '$CLIENT_SLUG' already exists at $CLIENT_DIR"
    read -rp "  Continue and add a project? [y/N]: " _cont
    [[ "$_cont" =~ ^[Yy]$ ]] || exit 0
else
    mkdir -p "$CLIENT_DIR/projects"

    if [[ -f "$TEMPLATE_DIR/client.instructions.md" ]]; then
        cp "$TEMPLATE_DIR/client.instructions.md" "$CLIENT_DIR/client.instructions.md"
    else
        cat > "$CLIENT_DIR/client.instructions.md" << CLIENTEOF
---
name: ${CLIENT_SLUG}
description: "Client context for ${CLIENT_NAME} — brand, voice, NAP data, stakeholders."
---

# ${CLIENT_NAME}

## Brand

- **Voice:**
- **Primary color:**
- **Website:**

## NAP (Name, Address, Phone)

- **Business name:** ${CLIENT_NAME}
- **Address:**
- **Phone:**
- **Email:**

## Stakeholders

- **Primary contact:**

## Key context

[Standing instructions about this client — preferences, patterns, past decisions.]
CLIENTEOF
    fi

    if command -v sed &>/dev/null; then
        sed -i.bak "s/\[Client Name\]/${CLIENT_NAME}/g" "$CLIENT_DIR/client.instructions.md" 2>/dev/null && rm -f "$CLIENT_DIR/client.instructions.md.bak" || true
    fi

    cat > "$CLIENT_DIR/.projects" << PROJMAPEOF
# .projects — Maps project directory paths to project slugs for ${CLIENT_NAME}
# Format: /path/to/project = project-slug
# Or:     /path/to/project   (client context only, no project context)
#
PROJMAPEOF

    green "Created client: $CLIENT_SLUG ($CLIENT_NAME)"
    green "  $CLIENT_DIR/client.instructions.md"
    green "  $CLIENT_DIR/.projects"
fi

echo ""
read -rp "  Map a project directory now? [Y/n]: " _map_project
if [[ ! "$_map_project" =~ ^[Nn]$ ]]; then
    read -rp "  Project directory path (e.g. ~/projects/alignsd-website): " _proj_path
    _proj_path="${_proj_path/#\~\//$HOME/}"

    read -rp "  Project slug (e.g. website): " _proj_slug

    if [[ ! -d "$_proj_path" ]]; then
        yellow "  Directory doesn't exist yet: $_proj_path"
        yellow "  Adding mapping anyway — will activate when directory exists"
    fi

    local_proj_dir="$CLIENT_DIR/projects/$_proj_slug"
    mkdir -p "$local_proj_dir"

    if [[ -f "$TEMPLATE_DIR/projects/_template/project.instructions.md" ]]; then
        cp "$TEMPLATE_DIR/projects/_template/project.instructions.md" "$local_proj_dir/project.instructions.md"
    else
        cat > "$local_proj_dir/project.instructions.md" << PROJEOF
---
name: ${_proj_slug}
description: "Project context for ${CLIENT_NAME} — ${_proj_slug}."
---

# ${_proj_slug} — ${CLIENT_NAME}

## Stack

- **Framework:**
- **CMS:**
- **Hosting:**

## Architecture decisions

[Decisions already made that the agent should not revisit.]

## Constraints

[Project-specific requirements or prohibitions.]
PROJEOF
    fi

    _stored_path="${_proj_path/$HOME/~}"
    printf '\n%s = %s\n' "$_stored_path" "$_proj_slug" >> "$CLIENT_DIR/.projects"

    green "  Mapped: $_stored_path = $_proj_slug"
    green "  Created: $local_proj_dir/project.instructions.md"
fi

echo ""
green "Client setup complete."
echo ""
echo "  Fill in client context:"
echo "  \$EDITOR $CLIENT_DIR/client.instructions.md"
echo ""
if [[ -n "${_proj_slug:-}" ]]; then
    echo "  Fill in project context:"
    echo "  \$EDITOR $local_proj_dir/project.instructions.md"
    echo ""
fi
echo "  Client loads automatically when you cd into a mapped project."
echo "  Test it: cd ${_proj_path:-~/projects/your-project} && echo \$ACTIVE_CLIENT"
echo ""
echo "  Add more projects:"
echo "  bash ~/dotfiles/bin/new-client.sh $CLIENT_SLUG"
