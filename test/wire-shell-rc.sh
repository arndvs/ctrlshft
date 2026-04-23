#!/usr/bin/env bash
# test/wire-shell-rc.sh — Regression tests for _wire_shell_rc() in bootstrap.sh.
# Tests the 3-way detection logic: markers present, legacy snippet, missing.
# Usage: bash test/wire-shell-rc.sh
# Exit: 0 if all pass, 1 if any fail.
set -euo pipefail

PASS=0
FAIL=0
FAILURES=()
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# ── Helpers ──────────────────────────────────────────────

green()  { printf "\033[32m%s\033[0m\n" "$*"; }
red()    { printf "\033[31m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }

_assert() {
    local label="$1"; shift
    if "$@"; then
        PASS=$((PASS + 1))
        printf "  \033[32m✓\033[0m %s\n" "$label"
    else
        FAIL=$((FAIL + 1))
        FAILURES+=("$label")
        printf "  \033[31m✗\033[0m %s\n" "$label"
    fi
}

_assert_file_contains() {
    local label="$1" file="$2" pattern="$3"
    _assert "$label" grep -qF "$pattern" "$file"
}

_assert_file_not_contains() {
    local label="$1" file="$2" pattern="$3"
    _assert "$label" bash -c "! grep -qF '$pattern' '$file'"
}

_assert_count() {
    local label="$1" file="$2" pattern="$3" expected="$4"
    local actual
    actual=$(grep -cF "$pattern" "$file" || true)
    _assert "$label (expected $expected, got $actual)" test "$actual" -eq "$expected"
}

# ── Extract _wire_shell_rc + deps from bootstrap.sh ──────

BOOTSTRAP="$(cd "$(dirname "$0")/.." && pwd)/bin/bootstrap.sh"

# Build a testable version: extract the snippet variable and function,
# stub the color helpers, and source it.
_HARNESS=$(cat <<'HARNESS'
green()  { :; }
yellow() { :; }
red()    { :; }
HARNESS
)

# Extract _SHELL_SNIPPET from bootstrap.sh
_SNIPPET_BLOCK=$(sed -n '/^_SHELL_SNIPPET=\$(cat << .SHELLEOF./,/^SHELLEOF$/p' "$BOOTSTRAP")
# Extract _wire_shell_rc function
_FUNC_BLOCK=$(sed -n '/^_wire_shell_rc() {$/,/^}$/p' "$BOOTSTRAP")

# Create a sourceable file
_SRC="$TMPDIR_ROOT/wire_shell_rc.sh"
cat > "$_SRC" <<'EOF'
#!/usr/bin/env bash
EOF
printf '%s\n' "$_HARNESS" >> "$_SRC"
printf '%s\n' "$_SNIPPET_BLOCK" >> "$_SRC"
printf '%s\n' ')' >> "$_SRC"
printf '%s\n' "$_FUNC_BLOCK" >> "$_SRC"

echo
echo "_wire_shell_rc() regression tests"
echo "════════════════════════════════════════════════"

# ── Test 1: Fresh file (no existing snippet) ─────────────

echo
echo "Case 1: Fresh RC file (no existing snippet)"
echo "────────────────────────────────────────────────"

_test1_dir="$TMPDIR_ROOT/test1"
mkdir -p "$_test1_dir"
cat > "$_test1_dir/.bashrc" <<'RC'
# user's existing config
export EDITOR=vim
alias ll='ls -la'
RC

(
    source "$_SRC"
    _wire_shell_rc "$_test1_dir/.bashrc" "~/.bashrc"
)

_assert_file_contains "appended BEGIN marker"    "$_test1_dir/.bashrc" "## BEGIN ctrlshft"
_assert_file_contains "appended END marker"      "$_test1_dir/.bashrc" "## END ctrlshft"
_assert_file_contains "has load-secrets"          "$_test1_dir/.bashrc" "load-secrets.sh"
_assert_file_contains "has PATH injection"        "$_test1_dir/.bashrc" '.local/bin'
_assert_file_contains "preserved user config"     "$_test1_dir/.bashrc" "export EDITOR=vim"
_assert_file_contains "preserved user alias"      "$_test1_dir/.bashrc" "alias ll="
_assert_count         "exactly 1 BEGIN marker"    "$_test1_dir/.bashrc" "## BEGIN ctrlshft" 1
_assert_count         "exactly 1 END marker"      "$_test1_dir/.bashrc" "## END ctrlshft" 1

# ── Test 2: Idempotent (run twice, no duplicate) ─────────

echo
echo "Case 2: Idempotent — run again, no duplicate"
echo "────────────────────────────────────────────────"

(
    source "$_SRC"
    _wire_shell_rc "$_test1_dir/.bashrc" "~/.bashrc"
)

_assert_count "still exactly 1 BEGIN marker" "$_test1_dir/.bashrc" "## BEGIN ctrlshft" 1
_assert_count "still exactly 1 END marker"   "$_test1_dir/.bashrc" "## END ctrlshft" 1
_assert_file_contains "user config preserved after re-run" "$_test1_dir/.bashrc" "export EDITOR=vim"

# ── Test 3: Legacy snippet (pre-markers) migration ───────

echo
echo "Case 3: Legacy snippet migration"
echo "────────────────────────────────────────────────"

_test3_dir="$TMPDIR_ROOT/test3"
mkdir -p "$_test3_dir"
cat > "$_test3_dir/.bashrc" <<'LEGACY'
# user's existing config
export EDITOR=vim
alias ll='ls -la'

# ── Secrets ──
[[ -f ~/dotfiles/bin/load-secrets.sh ]] && source ~/dotfiles/bin/load-secrets.sh

# ── dotfiles/cli (ctrl + shft) ──
[[ -d "$HOME/.local/bin" ]] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin:$PATH"

# ── dotfiles/context-detection ──
_load_context() {
    [[ -f ~/dotfiles/bin/detect-context.sh ]] \
        && source ~/dotfiles/bin/detect-context.sh > /dev/null 2>&1
    [[ -f ~/dotfiles/bin/detect-client.sh ]] \
        && source ~/dotfiles/bin/detect-client.sh > /dev/null 2>&1
}
cd() { builtin cd "$@" && _load_context; }
_load_context
LEGACY

(
    source "$_SRC"
    _wire_shell_rc "$_test3_dir/.bashrc" "~/.bashrc"
)

_assert_file_contains "has BEGIN marker after migration"  "$_test3_dir/.bashrc" "## BEGIN ctrlshft"
_assert_file_contains "has END marker after migration"    "$_test3_dir/.bashrc" "## END ctrlshft"
_assert_file_contains "user config preserved"             "$_test3_dir/.bashrc" "export EDITOR=vim"
_assert_file_contains "user alias preserved"              "$_test3_dir/.bashrc" "alias ll="
_assert_count         "exactly 1 BEGIN marker"            "$_test3_dir/.bashrc" "## BEGIN ctrlshft" 1
_assert_count         "exactly 1 load-secrets ref"        "$_test3_dir/.bashrc" "load-secrets.sh" 1
_assert_file_not_contains "legacy header removed"         "$_test3_dir/.bashrc" "# ── Secrets ──"

# Verify backup was created
_assert "backup created for legacy migration" bash -c 'ls "$1"/.bashrc.bak.* >/dev/null 2>&1' _ "$_test3_dir"

# ── Test 4: Updated snippet replaces old managed block ───

echo
echo "Case 4: Snippet update replaces managed block"
echo "────────────────────────────────────────────────"

_test4_dir="$TMPDIR_ROOT/test4"
mkdir -p "$_test4_dir"
cat > "$_test4_dir/.bashrc" <<'OLD_MANAGED'
## BEGIN ctrlshft

# old version of the snippet
[[ -f ~/dotfiles/bin/load-secrets.sh ]] && source ~/dotfiles/bin/load-secrets.sh
# MISSING: no PATH injection, no HUD, no context-detection

## END ctrlshft

# user config below
export EDITOR=vim
OLD_MANAGED

(
    source "$_SRC"
    _wire_shell_rc "$_test4_dir/.bashrc" "~/.bashrc"
)

_assert_file_contains "updated to include PATH injection"   "$_test4_dir/.bashrc" '.local/bin'
_assert_file_contains "updated to include HUD"              "$_test4_dir/.bashrc" "write-hud-state.sh"
_assert_file_contains "updated to include context-detect"   "$_test4_dir/.bashrc" "_load_context"
_assert_file_contains "user config preserved after update"  "$_test4_dir/.bashrc" "export EDITOR=vim"
_assert_count         "exactly 1 BEGIN after update"        "$_test4_dir/.bashrc" "## BEGIN ctrlshft" 1
_assert_count         "exactly 1 END after update"          "$_test4_dir/.bashrc" "## END ctrlshft" 1
_assert_file_not_contains "old comment removed" "$_test4_dir/.bashrc" "MISSING: no PATH"

# ── Test 5: Empty file ───────────────────────────────────

echo
echo "Case 5: Empty RC file"
echo "────────────────────────────────────────────────"

_test5_dir="$TMPDIR_ROOT/test5"
mkdir -p "$_test5_dir"
touch "$_test5_dir/.bashrc"

(
    source "$_SRC"
    _wire_shell_rc "$_test5_dir/.bashrc" "~/.bashrc"
)

_assert_file_contains "snippet added to empty file"   "$_test5_dir/.bashrc" "## BEGIN ctrlshft"
_assert_file_contains "has load-secrets"               "$_test5_dir/.bashrc" "load-secrets.sh"

# ── Test 6: File with unrelated load-secrets reference ───

echo
echo "Case 6: User has own load-secrets reference (not legacy block)"
echo "────────────────────────────────────────────────"

_test6_dir="$TMPDIR_ROOT/test6"
mkdir -p "$_test6_dir"
cat > "$_test6_dir/.bashrc" <<'CUSTOM'
# my custom setup
source ~/my-scripts/load-secrets.sh
export FOO=bar
CUSTOM

(
    source "$_SRC"
    _wire_shell_rc "$_test6_dir/.bashrc" "~/.bashrc"
)

# This should NOT trigger the legacy path (no "# ── Secrets ──" header)
# but WILL trigger the legacy path because it matches "load-secrets.sh" grep.
# Document the actual behavior:
_assert_file_contains "has managed markers"  "$_test6_dir/.bashrc" "## BEGIN ctrlshft"
_assert_file_contains "user FOO preserved"   "$_test6_dir/.bashrc" "export FOO=bar"

# ── Summary ──────────────────────────────────────────────

echo
echo "════════════════════════════════════════════════"
printf "  \033[32m%d passed\033[0m  " "$PASS"
printf "\033[31m%d failed\033[0m\n" "$FAIL"

if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo
    echo "  Failures:"
    for f in "${FAILURES[@]}"; do
        printf "    \033[31m✗\033[0m %s\n" "$f"
    done
    echo
    exit 1
fi

echo
exit 0
