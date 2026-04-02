#!/usr/bin/env bash
# bootstrap.sh — Set up ~/dotfiles on a fresh machine.
#
# Usage:
#   cd ~/dotfiles && bash bin/bootstrap.sh
#
# Idempotent — safe to re-run. Skips steps that are already done.
# Works on: Windows (Git Bash), Linux (VPS), macOS.

set -euo pipefail

DOTFILES="$HOME/dotfiles"
CLAUDE_DIR="$HOME/.claude"
SECRETS_DIR="$DOTFILES/secrets"
VENV_DIR="$SECRETS_DIR/.venv"

# ── Colors ────────────────────────────────────────────────────────────────────
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
red()    { printf '\033[31m%s\033[0m\n' "$*"; }

# ── OS detection ──────────────────────────────────────────────────────────────
detect_os() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        Linux*)               echo "linux"   ;;
        Darwin*)              echo "macos"   ;;
        *)                    echo "unknown" ;;
    esac
}

OS=$(detect_os)
green "Detected OS: $OS"

# Track failures across all steps
_fail=0

# ── Verify we're inside the dotfiles repo ─────────────────────────────────────
if [[ ! -f "$DOTFILES/CLAUDE.md" ]]; then
    red "Error: $DOTFILES/CLAUDE.md not found."
    red "Clone the repo first: git clone <repo-url> ~/dotfiles"
    exit 1
fi

# ── 1. Create secrets directory and .env from template ────────────────────────
echo
green "[1/6] Secrets directory"
mkdir -p "$SECRETS_DIR"
if [[ -f "$SECRETS_DIR/.env" ]]; then
    yellow "  secrets/.env already exists — skipping"
else
    if [[ ! -f "$DOTFILES/.env.example" ]]; then
        red "  Error: $DOTFILES/.env.example not found — cannot create secrets/.env"
        red "  This file should exist in the repo. Try: git checkout -- .env.example"
        exit 1
    fi
    cp "$DOTFILES/.env.example" "$SECRETS_DIR/.env"
    green "  Created secrets/.env from .env.example"
    yellow "  >>> Fill in your API keys: $SECRETS_DIR/.env"
fi

# ── 2. Symlink ~/.claude/CLAUDE.md ────────────────────────────────────────────
echo
green "[2/6] CLAUDE.md"
mkdir -p "$CLAUDE_DIR"
if [[ -L "$CLAUDE_DIR/CLAUDE.md" ]]; then
    _target=$(readlink "$CLAUDE_DIR/CLAUDE.md")
    if [[ "$_target" == "$DOTFILES/CLAUDE.md" ]]; then
        yellow "  ~/.claude/CLAUDE.md is already symlinked correctly — skipping"
    else
        ln -sf "$DOTFILES/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
        green "  Fixed stale symlink (was $_target)"
    fi
elif [[ "$OS" == "windows" ]]; then
    cp "$DOTFILES/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
    yellow "  Copied CLAUDE.md (Windows: file symlinks require admin)"
    yellow "  To upgrade to a symlink, run as admin:"
    yellow "    cmd /c mklink C:\\Users\\%USERNAME%\\.claude\\CLAUDE.md C:\\Users\\%USERNAME%\\dotfiles\\CLAUDE.md"
else
    [[ -f "$CLAUDE_DIR/CLAUDE.md" ]] && yellow "  Replacing regular file with symlink"
    ln -sf "$DOTFILES/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
    green "  Symlinked ~/.claude/CLAUDE.md -> ~/dotfiles/CLAUDE.md"
fi

# ── 3. Symlink ~/.claude/skills/ ──────────────────────────────────────────────
echo
green "[3/6] Skills directory"
if [[ -L "$CLAUDE_DIR/skills" ]]; then
    _target=$(readlink "$CLAUDE_DIR/skills")
    if [[ "$_target" == "$DOTFILES/skills" ]]; then
        yellow "  ~/.claude/skills is already symlinked correctly — skipping"
    else
        ln -sf "$DOTFILES/skills" "$CLAUDE_DIR/skills"
        green "  Fixed stale skills symlink (was $_target)"
    fi
elif [[ -d "$CLAUDE_DIR/skills" ]]; then
    yellow "  ~/.claude/skills exists as a real directory — skipping (manual merge needed)"
else
    ln -sf "$DOTFILES/skills" "$CLAUDE_DIR/skills"
    if [[ -L "$CLAUDE_DIR/skills" ]]; then
        green "  Symlinked ~/.claude/skills -> ~/dotfiles/skills/"
    elif [[ "$OS" == "windows" ]]; then
        red "  Symlink creation failed — Windows requires Developer Mode for directory symlinks."
        red "  Enable Developer Mode: Settings > Privacy > For Developers > Developer Mode"
        red "  Then re-run this script."
        _fail=1
    else
        red "  Symlink creation failed — check permissions"
        _fail=1
    fi
fi

# ── 4. Wire up shell ──────────────────────────────────────────────────────────
echo
green "[4/6] Shell integration"

_SHELL_SNIPPET=$(cat << 'SHELLEOF'

# ── dotfiles/load-secrets ──
[[ -f ~/dotfiles/bin/load-secrets.sh ]] && source ~/dotfiles/bin/load-secrets.sh

# ── dotfiles/context-detection ──
_load_context() {
    [[ -f ~/dotfiles/bin/detect-context.sh ]] \
        && source ~/dotfiles/bin/detect-context.sh > /dev/null 2>&1
}
cd() { builtin cd "$@" && _load_context; }
_load_context
SHELLEOF
)

_wire_shell_rc() {
    local rc_file="$1"
    local rc_name="$2"
    if [[ -f "$rc_file" ]] && grep -qF "load-secrets.sh" "$rc_file"; then
        yellow "  $rc_name already sources load-secrets — skipping"
    else
        printf '%s\n' "$_SHELL_SNIPPET" >> "$rc_file"
        green "  Appended load-secrets and context-detection to $rc_name"
    fi
}

BASHRC="$HOME/.bashrc"
ZSHRC="$HOME/.zshrc"

_wire_shell_rc "$BASHRC" "~/.bashrc"
if [[ -f "$ZSHRC" ]] || [[ "$(basename "$SHELL" 2>/dev/null)" == "zsh" ]]; then
    _wire_shell_rc "$ZSHRC" "~/.zshrc"
fi

# ── 5. Python venv ───────────────────────────────────────────────────────────
echo
green "[5/6] Python venv"

# Find a python executable (venv first, then system)
PYTHON=""
if [[ -f "$VENV_DIR/Scripts/python.exe" ]]; then
    PYTHON="$VENV_DIR/Scripts/python.exe"
elif [[ -f "$VENV_DIR/bin/python" ]]; then
    PYTHON="$VENV_DIR/bin/python"
else
    for cmd in python3 python; do
        if "$cmd" --version &>/dev/null 2>&1; then
            PYTHON="$cmd"
            break
        fi
    done
fi

if [[ -z "$PYTHON" ]]; then
    yellow "  Python not found — skipping venv setup"
    yellow "  Install Python 3.10+ and re-run this script"
elif [[ -d "$VENV_DIR" ]]; then
    # Verify venv is functional, not just present
    _venv_python=""
    [[ -f "$VENV_DIR/Scripts/python.exe" ]] && _venv_python="$VENV_DIR/Scripts/python.exe"
    [[ -f "$VENV_DIR/bin/python" ]] && _venv_python="$VENV_DIR/bin/python"
    if [[ -n "$_venv_python" ]] && "$_venv_python" --version &>/dev/null; then
        yellow "  Venv already exists at $VENV_DIR — skipping"
    else
        red "  Venv directory exists but Python binary is broken: $VENV_DIR"
        red "  Fix with: rm -rf $VENV_DIR && bash ~/dotfiles/bin/bootstrap.sh"
        _fail=1
    fi
else
    green "  Creating venv with $PYTHON..."
    "$PYTHON" -m venv "$VENV_DIR"

    # Activate (cross-platform)
    if [[ "$OS" == "windows" ]]; then
        source "$VENV_DIR/Scripts/activate"
    else
        source "$VENV_DIR/bin/activate"
    fi

    pip install --quiet google-auth google-auth-httplib2 google-api-python-client
    green "  Venv created and base packages installed"
fi

# ── 6. Validation ─────────────────────────────────────────────────────────────
echo
green "[6/6] Validating setup"

if [[ "$OS" == "windows" ]]; then
    if [[ -f "$CLAUDE_DIR/CLAUDE.md" ]]; then
        green "  ✓ ~/.claude/CLAUDE.md exists"
    else
        red "  ✗ ~/.claude/CLAUDE.md missing"; _fail=1
    fi
else
    if [[ -L "$CLAUDE_DIR/CLAUDE.md" ]] && [[ -f "$CLAUDE_DIR/CLAUDE.md" ]]; then
        green "  ✓ ~/.claude/CLAUDE.md is a symlink (target resolves)"
    elif [[ -L "$CLAUDE_DIR/CLAUDE.md" ]]; then
        red "  ✗ ~/.claude/CLAUDE.md is a dangling symlink — target missing"; _fail=1
    else
        red "  ✗ ~/.claude/CLAUDE.md is not a symlink — re-run bootstrap"; _fail=1
    fi
fi

if [[ -L "$CLAUDE_DIR/skills" ]] && [[ -d "$CLAUDE_DIR/skills" ]]; then
    green "  ✓ ~/.claude/skills is a symlink (target resolves)"
elif [[ -L "$CLAUDE_DIR/skills" ]]; then
    red "  ✗ ~/.claude/skills is a dangling symlink — target missing"; _fail=1
else
    red "  ✗ ~/.claude/skills missing or not a symlink"; _fail=1
fi

if [[ -f "$SECRETS_DIR/.env" ]]; then
    green "  ✓ secrets/.env exists"
else
    red "  ✗ secrets/.env missing"; _fail=1
fi

if [[ -f "$BASHRC" ]] && grep -qF "load-secrets.sh" "$BASHRC"; then
    green "  ✓ .bashrc has load-secrets integration"
else
    red "  ✗ .bashrc missing load-secrets integration"; _fail=1
fi

if [[ -f "$ZSHRC" ]]; then
    if grep -qF "load-secrets.sh" "$ZSHRC"; then
        green "  ✓ .zshrc has load-secrets integration"
    else
        red "  ✗ .zshrc exists but missing load-secrets integration"; _fail=1
    fi
fi

if [[ -d "$VENV_DIR" ]]; then
    green "  ✓ Python venv exists"
else
    yellow "  ~ Python venv not created (Python not found)"
fi

echo
if [[ $_fail -eq 0 ]]; then
    green "All checks passed!"
else
    red "Some checks failed — review the output above."
fi

echo ""
echo "Next steps:"
_step=1
if [[ ! -s "$SECRETS_DIR/.env" ]] || grep -q "^GITHUB_USERNAME=$" "$SECRETS_DIR/.env" 2>/dev/null; then
    yellow "  $_step. Fill in secrets:  \$EDITOR ~/dotfiles/secrets/.env"
    ((_step++))
fi
echo "  $_step. Reload shell:    source ~/.bashrc"
((_step++))
if [[ -d "$HOME/.vscode-server" ]]; then
    echo "  $_step. Sync VS Code settings on your LOCAL machine (not this VPS)"
else
    echo "  $_step. Merge VS Code settings:  bash ~/dotfiles/bin/sync-settings.sh"
fi
((_step++))
echo "  $_step. Verify:          echo \$GITHUB_USERNAME"

exit $_fail
