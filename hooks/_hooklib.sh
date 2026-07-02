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
