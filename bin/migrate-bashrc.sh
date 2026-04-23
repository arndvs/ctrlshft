#!/usr/bin/env bash
# One-time migration: replace legacy .bashrc snippet with managed version.
# Safe to run multiple times — idempotent after first migration.
# Usage: bash ~/dotfiles/bin/migrate-bashrc.sh

set -euo pipefail

green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
red()    { printf '\033[31m%s\033[0m\n' "$*"; }

BASHRC="$HOME/.bashrc"

if [[ ! -f "$BASHRC" ]]; then
    red "No ~/.bashrc found — nothing to migrate"
    exit 1
fi

# Already migrated?
if grep -qF "## BEGIN ctrlshft" "$BASHRC"; then
    yellow "~/.bashrc already has ## BEGIN/END ctrlshft markers — nothing to do"
    exit 0
fi

# Must have the legacy snippet to migrate
if ! grep -qF "load-secrets.sh" "$BASHRC"; then
    yellow "~/.bashrc has no legacy snippet — nothing to migrate"
    exit 0
fi

# ── Backup ────────────────────────────────────────────────────────────────────
BACKUP="${BASHRC}.bak.$(date +%s)"
cp "$BASHRC" "$BACKUP"
green "Backed up to $BACKUP"

# ── Extract user content (everything after the legacy block) ──────────────────
# Legacy block: starts at "# ── Secrets" or "# ── dotfiles/load-secrets"
# and ends at the standalone "_load_context" call (+ trailing blank line)
USER_CONTENT=$(awk '
    /^# ── Secrets ──/ || /^# ── dotfiles\/load-secrets ──/ { skip=1 }
    skip && /^_load_context[[:space:]]*$/ { skip=0; next }
    !skip { print }
' "$BASHRC")

# ── Write new file: managed snippet first, then user content ──────────────────
cat > "$BASHRC" << 'MANAGED'

## BEGIN ctrlshft

# ── dotfiles/load-secrets ──
[[ -f ~/dotfiles/bin/load-secrets.sh ]] && source ~/dotfiles/bin/load-secrets.sh

# ── dotfiles/cli (ctrl + shft) ──
[[ -d "$HOME/.local/bin" ]] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin:$PATH"

# ── dotfiles/hud ──
[[ -f ~/dotfiles/bin/write-hud-state.sh ]] && source ~/dotfiles/bin/write-hud-state.sh
[[ -x ~/dotfiles/bin/ctrlshft-claude ]] && alias claude='~/dotfiles/bin/ctrlshft-claude'

# ── dotfiles/context-detection ──
_load_context() {
    [[ -f ~/dotfiles/bin/detect-context.sh ]] \
        && source ~/dotfiles/bin/detect-context.sh > /dev/null 2>&1
    [[ -f ~/dotfiles/bin/detect-client.sh ]] \
        && source ~/dotfiles/bin/detect-client.sh > /dev/null 2>&1
}
cd() { builtin cd "$@" && _load_context; }
_load_context

## END ctrlshft
MANAGED

printf '%s\n' "$USER_CONTENT" >> "$BASHRC"

green "Migrated ~/.bashrc — legacy snippet replaced with managed ## BEGIN/END ctrlshft block"
echo
echo "Verify with:  source ~/.bashrc && which ctrl && which shft"
