#!/usr/bin/env bash
# _hooklib.sh — Shared library for hooks/ scripts.
#
# Source this AFTER the hook establishes its `set` options and fail-mode `trap`.
# Fail-mode is a per-hook decision, so this library never sets `set` options or
# installs traps, and reads no stdin — it only defines shared constants and
# helpers. If the library is missing or unparsable, the sourcing `source` fails
# under the hook's own `set -e` + ERR trap, so each hook's declared fail mode
# (closed → deny, open → allow) governs the outcome automatically.
#
# Sourcing pattern (after `set` and `trap`):
#   source "$(dirname "${BASH_SOURCE[0]}")/_hooklib.sh"
#
# Provides:
#   WRAPPER_PREFIX — canonical command-wrapper regex.
#   COMMAND_BOUNDARY — command-start regex without backtick boundaries.
#   COMMAND_BOUNDARY_WITH_BACKTICK — command-start regex for hooks that
#       already treated backticks as command boundaries before extraction.
#
# Keep this file dependency-free (POSIX shell + the tools hooks already require)
# and side-effect-free (definitions only).

# ── WRAPPER_PREFIX ────────────────────────────────────────────────────────────
# Canonical command-wrapper prefix regex (POSIX ERE). Fail-closed hooks anchor
# their command matching with this so gates cannot be bypassed by wrapping the
# target command in sudo/env/command/builtin, e.g. `sudo git push --force`,
# `env FOO=bar echo $SECRET`, `command git commit`.
#
# `sudo` and `env` may carry flags with optional arguments (e.g. `sudo -u root`,
# `env -u VARNAME FOO=bar`, `env --unset=VARNAME`) before the wrapped command;
# GNU-style long options with inline `=value` (`--opt=val`) are also consumed.
#
# SECURITY-CRITICAL: this is the single source of truth. A change here applies to
# every hook that detects command wrappers. Do NOT copy it back inline — the
# hooks integration suite asserts it is defined only in this file.
WRAPPER_PREFIX='(sudo([[:space:]]+-[-a-zA-Z0-9]+(=[^[:space:]]+)?([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+|command[[:space:]]+|builtin[[:space:]]+|env([[:space:]]+-[-a-zA-Z0-9]+(=[^[:space:]]+)?([[:space:]]+[^-[:space:]=][^[:space:]]*)?)*([[:space:]]+[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*)*[[:space:]]+)*'

# ── _timeout ─────────────────────────────────────────────────────────────────
# Portable timeout wrapper. macOS ships without GNU coreutils timeout.
# Returns 1 when no timeout utility is available so callers that use
# `if _timeout ...` gracefully skip bounded operations rather than hanging.
_timeout() {
    if command -v timeout &>/dev/null; then
        timeout "$@"
    else
        return 1
    fi
}

# ── _deny ─────────────────────────────────────────────────────────────────────
# Standard output helper for PreToolUse fail-closed hooks.
# Exits 2 (block) with a JSON permissionDecision payload on stderr.
_deny() {
    jq -cn --arg reason "$1" '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":$reason}}' >&2
    exit 2
}

# ── COMMAND_BOUNDARY / ASSIGNMENT_PREFIX ─────────────────────────────────────
# Shared regex fragments for anchoring pattern detection to shell command
# boundaries. A "command boundary" is any position where a new command can
# start: start of string (^), after shell separators (; | ( {), after compound
# operators (&& || $(), or after control keywords (then/do/else).
#
# COMMAND_BOUNDARY intentionally excludes backticks to preserve hooks that did
# not treat legacy command substitution as a boundary before the extraction.
# Use COMMAND_BOUNDARY_WITH_BACKTICK only for hooks that already had that
# broader behavior.
#
# SECURITY-CRITICAL: changing these constants affects every hook that detects
# command patterns. Test with bash test/hooks-integration.sh after any edit.
COMMAND_BOUNDARY='((^|[;|({]|&&|\|\||\$\()[[:space:]]*|(^|[[:space:]])(then|do|else)[[:space:]]+)'
COMMAND_BOUNDARY_WITH_BACKTICK='((^|[;|({`]|&&|\|\||\$\()[[:space:]]*|(^|[[:space:]])(then|do|else)[[:space:]]+)'
ASSIGNMENT_PREFIX='([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
