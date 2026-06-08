# bin

CLI scripts and infrastructure. Bootstrap symlinks `ctrl` and `shft` to `~/.local/bin/`; the rest are internal.

## User-Facing CLIs

| Script | Purpose |
|--------|---------|
| `ctrl` | Manage your environment — `ctrl bootstrap`, `ctrl check`, `ctrl sync` |
| `ctrlshft-claude` | Claude Code wrapper that parses stdout and emits HUD events |

## Bootstrap & Propagation

| Script | Purpose |
|--------|---------|
| `bootstrap.sh` | 13-step idempotent setup — symlinks, shell integration, supply chain protection |
| `validate-symlinks.sh` | Verify every consumer path is a valid symlink (or byte-identical Windows copy) |
| `validate-env.sh` | Validate environment — secrets, tools, permissions |
| `sync-settings.sh` | Merge VS Code settings from `settings.json` into the active profile |
| `migrate.sh` | One-time migration scripts for breaking changes |
| `migrate-bashrc.sh` | Migrate legacy shell integration blocks |
| `_adopt.sh` | Adopt an existing clone into the ctrl+shft structure |
| `uninstall.sh` | Remove all symlinks, shell integration, and consumer targets |

## Context Detection

| Script | Purpose |
|--------|---------|
| `detect-context.sh` | Scan `$PWD` for file signatures → export `$ACTIVE_CONTEXTS` |
| `detect-client.sh` | Map `$PWD` to a client/project → write `working/active-client.md` |

## Secret Management

| Script | Purpose |
|--------|---------|
| `load-secrets.sh` | Source `.env.agent` into shell environment (config only, not credentials) |
| `run-with-secrets.sh` | Execute a command with credentials in a child process — credentials vanish on exit |
| `mint_github_app_token.py` | Mint short-lived GitHub App installation tokens for AFK loops |
| `verify-github-app-token.sh` | Test that token minting works before starting AFK |
| `gh-assignee-preflight.sh` | Verify `gh` auth/token context can assign issues before running `gh issue edit --add-assignee` |

## HUD Infrastructure

| Script | Purpose |
|--------|---------|
| `hud-daemon.js` | Zero-dependency Node.js HTTP/WebSocket server (ports 7823/7822) |
| `start-hud.sh` | Start/restart the HUD daemon |
| `write-hud-state.sh` | Canonical event emitter — `source` it, then call `write_hud_event` |
| `com.ctrlshft.hud.plist` | macOS launchd service definition for auto-starting HUD |
| `ctrlshft-hud.service` | Linux systemd service definition for auto-starting HUD |

## Internal Utilities

| Script | Purpose |
|--------|---------|
| `_lib.sh` | Shared functions — `green()`, `red()`, `yellow()`, `ensure_symlink()`, `find_python()`, `detect_os()` |
| `drift-detect.sh` | Check if bootstrap targets have diverged from source |
| `agent-shell.sh` | Shell wrapper for agent subprocesses |
| `new-client.sh` | Scaffold a new client directory from `clients/_template/` |
