#!/usr/bin/env bash
# sync-settings.sh — Merge ~/dotfiles/settings.json into VS Code user settings.
#
# Usage:
#   bash ~/dotfiles/bin/sync-settings.sh            # merge into VS Code Insiders
#   bash ~/dotfiles/bin/sync-settings.sh --stable    # merge into stable VS Code
#   bash ~/dotfiles/bin/sync-settings.sh --dry-run   # show what would change
#
# Creates a timestamped backup before writing. Additive merge — never deletes
# keys from user settings, only adds or updates keys from dotfiles.
#
# Requires: python3 (or python on Windows)

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

DRY_RUN=false
VARIANT="insiders"

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --stable)  VARIANT="stable" ;;
    esac
done

# ── Guard: skip on VPS / Remote SSH targets ───────────────────────────────────
if [[ -d "$HOME/.vscode-server" ]]; then
    echo "Error: This appears to be a VS Code Remote SSH target (VPS)."
    echo "VS Code settings are managed on your LOCAL machine — Remote SSH forwards them automatically."
    echo "Run sync-settings.sh on your local machine instead."
    exit 1
fi

# ── Locate settings file ─────────────────────────────────────────────────────
case "$(detect_os)" in
    windows)
        if [[ "$VARIANT" == "stable" ]]; then
            USER_SETTINGS="$APPDATA/Code/User/settings.json"
        else
            USER_SETTINGS="$APPDATA/Code - Insiders/User/settings.json"
        fi
        ;;
    macos)
        if [[ "$VARIANT" == "stable" ]]; then
            USER_SETTINGS="$HOME/Library/Application Support/Code/User/settings.json"
        else
            USER_SETTINGS="$HOME/Library/Application Support/Code - Insiders/User/settings.json"
        fi
        ;;
    linux)
        if [[ "$VARIANT" == "stable" ]]; then
            USER_SETTINGS="$HOME/.config/Code/User/settings.json"
        else
            USER_SETTINGS="$HOME/.config/Code - Insiders/User/settings.json"
        fi
        ;;
    *)
        echo "Unsupported OS"; exit 1
        ;;
esac

DOTFILES_SETTINGS="$HOME/dotfiles/settings.json"

if [[ ! -f "$DOTFILES_SETTINGS" ]]; then
    echo "Error: $DOTFILES_SETTINGS not found"
    exit 1
fi

if [[ ! -f "$USER_SETTINGS" ]]; then
    echo "Error: $USER_SETTINGS not found"
    echo "Open VS Code at least once to create the settings file."
    exit 1
fi

# ── Find Python ───────────────────────────────────────────────────────────────
VENV_DIR="$HOME/dotfiles/secrets/.venv"
if ! find_python; then
    echo "Error: Python not found"
    exit 1
fi

# ── Run merge via Python (handles JSONC comments, deep merge) ─────────────────
"$PYTHON" -c "
import json
import re
import sys
import shutil
from datetime import datetime
from pathlib import Path

dotfiles_path = Path(sys.argv[1])
user_path = Path(sys.argv[2])
dry_run = sys.argv[3] == 'true'

def strip_jsonc(text):
    \"\"\"Remove // and /* */ comments from JSONC, preserving strings.\"\"\"
    result = []
    i = 0
    in_string = False
    escape = False
    while i < len(text):
        c = text[i]
        if escape:
            result.append(c)
            escape = False
            i += 1
            continue
        if in_string:
            result.append(c)
            if c == '\\\\':
                escape = True
            elif c == '\"':
                in_string = False
            i += 1
            continue
        if c == '\"':
            in_string = True
            result.append(c)
            i += 1
            continue
        if c == '/' and i + 1 < len(text):
            if text[i + 1] == '/':
                while i < len(text) and text[i] != '\n':
                    i += 1
                continue
            elif text[i + 1] == '*':
                i += 2
                while i + 1 < len(text) and not (text[i] == '*' and text[i + 1] == '/'):
                    i += 1
                i += 2
                continue
        result.append(c)
        i += 1
    return ''.join(result)

def strip_trailing_commas(text):
    \"\"\"Remove trailing commas before } or ] in JSON.\"\"\"
    return re.sub(r',\s*([}\]])', r'\1', text)

def parse_jsonc(path):
    raw = path.read_text(encoding='utf-8')
    cleaned = strip_trailing_commas(strip_jsonc(raw))
    return json.loads(cleaned)

def deep_merge(base, overlay):
    \"\"\"Merge overlay into base. Overlay wins for scalar values.
    For dicts, recurse. For lists, overlay replaces entirely.\"\"\"
    merged = dict(base)
    for key, val in overlay.items():
        if key in merged and isinstance(merged[key], dict) and isinstance(val, dict):
            merged[key] = deep_merge(merged[key], val)
        else:
            merged[key] = val
    return merged

dotfiles = parse_jsonc(dotfiles_path)
user = parse_jsonc(user_path)

merged = deep_merge(user, dotfiles)

added = [k for k in dotfiles if k not in user]
updated = [k for k in dotfiles if k in user and user[k] != dotfiles[k]]
unchanged = len(dotfiles) - len(added) - len(updated)

print(f'Dotfiles keys: {len(dotfiles)}')
print(f'User keys:     {len(user)}')
print(f'Result keys:   {len(merged)}')
print(f'Added:         {len(added)}')
print(f'Updated:       {len(updated)}')
print(f'Unchanged:     {unchanged}')

if added:
    print(f'\nNew keys: {added[:10]}' + (' ...' if len(added) > 10 else ''))
if updated:
    print(f'Changed keys: {updated[:10]}' + (' ...' if len(updated) > 10 else ''))

if dry_run:
    print('\n--dry-run: no changes written')
    sys.exit(0)

if not added and not updated:
    print('\nAlready in sync — nothing to do')
    sys.exit(0)

backup = user_path.with_suffix(f'.backup-{datetime.now().strftime(\"%Y%m%d-%H%M%S\")}.json')
shutil.copy2(user_path, backup)
print(f'\nBackup: {backup}')

user_path.write_text(json.dumps(merged, indent='\t', ensure_ascii=False) + '\n', encoding='utf-8')
print(f'Merged settings written to {user_path}')
print('Restart VS Code to apply changes.')
" "$DOTFILES_SETTINGS" "$USER_SETTINGS" "$DRY_RUN"
