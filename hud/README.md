# HUD

Real-time compliance visibility for ctrl+shft agent sessions — which rules loaded, which skills fired, and whether they were followed.

## Quick Start

```bash
ctrl dashboard
# Visit http://localhost:7823
```

Alternatively: `bash ~/dotfiles/bin/start-hud.sh`

## Lifecycle Commands

| Command                                             | What it does                         |
| --------------------------------------------------- | ------------------------------------ |
| `ctrl dashboard`                                    | Start daemon (default, background)   |
| `ctrl dashboard stop`                               | Stop daemon                          |
| `ctrl dashboard status`                             | Check if running, show PID and URL   |
| `ctrl dashboard restart`                            | Stop + start                         |
| `ctrl dashboard logs [-f]`                          | Show daemon log (add `-f` to follow) |
| `ctrl dashboard events`                             | Recent events for current project    |
| `ctrl dashboard violations`                         | Violations for current project       |
| `ctrl dashboard state`                              | Full debug state dump (JSON)         |
| `ctrl dashboard clear`                              | Clear events for a project           |
| `ctrl dashboard open`                               | Open HUD in browser                  |
| `ctrl dashboard url`                                | Print the HUD URL                    |
| `bash ~/dotfiles/bin/start-hud.sh foreground`       | Run in foreground (no daemonization) |

Port defaults to `7823`. Override with `HUD_PORT=8080 ctrl dashboard`.

## Architecture

```
Event Producers                              Transport priority:
  │                                            1. Named pipe (hud.pipe)
  ├── ctrlshft-claude                          2. HTTP POST (:7823/api/event)
  │     Parses Claude stdout for Read/         3. JSONL append (events.jsonl)
  │     compliance/context events              
  ├── detect-context.sh                      
  │     Inline push on every cd()            
  ├── detect-client.sh                       
  │     Client context change events         
  ├── shft/afk.sh                            
  │     AFK iteration start/end events       
  └── write-hud-state.sh               
        Sourceable functions for manual use  
        │
        ▼
hud-daemon.js
  ├── Named pipe listener (real-time, <1ms)
  ├── JSONL file watcher (AFK/Docker fallback)
  ├── SQLite persistence (optional, via better-sqlite3)
  ├── In-memory session + event buffers
  ├── WebSocket server (ws://localhost:7822)
  └── HTTP server (:7823) — HUD UI + REST API
```

## API Endpoints

| Method | Path                        | Description                                            |
| ------ | --------------------------- | ------------------------------------------------------ |
| GET    | `/`                         | Serves HUD UI (`hud/index.html`)           |
| GET    | `/api/state`                | Returns current compliance state as JSON               |
| GET    | `/api/events/:project`      | Project event history (query: `?limit=200`)            |
| GET    | `/api/violations/:project`  | Project violations (SQLite only)                       |
| GET    | `/api/compliance-log`       | Raw compliance-log.md content                          |
| POST   | `/api/event`                | Receives compliance events (JSON body)                 |

WebSocket: `ws://localhost:7822` — real-time event broadcasts + heartbeat.

## Event Types

Events emitted by `write-hud-state.sh`:

| Type                | Source              | Description                                    |
| ------------------- | ------------------- | ---------------------------------------------- |
| `context`           | `detect-context.sh` | Active project contexts (nextjs, sanity, etc.) |
| `info`              | Various             | Informational messages                         |
| `read`              | Skill loading       | File read tracking (loaded rules/skills/agents)|
| `compliance_update` | `compliance-audit`  | Structured compliance result (pass/fail/warn)  |
| `compliance-result` | Legacy callers      | Backward-compat compliance event               |
| `pass`              | Rule check          | Rule compliance passed                         |
| `fail`              | Rule check          | Rule compliance failed (creates violation)     |
| `warn`              | Rule check          | Rule compliance warning                        |

## Data Persistence

All runtime data lives in `working/` (gitignored):

- `working/events.jsonl` — append-only event log
- `working/hud.db` — SQLite database (if better-sqlite3 installed)
- `working/hud.pipe` — named pipe for real-time events (Unix only)
- `working/hud-state.json` — legacy aggregated state (fallback)
- `working/hud-daemon.pid` — daemon PID file
- `working/hud-daemon.log` — daemon stdout/stderr log

## Optional: SQLite Persistence

Install `better-sqlite3` for persistent history across daemon restarts:

```bash
cd ~/dotfiles && npm install better-sqlite3
```

Without it, the daemon uses in-memory buffers + JSONL fallback. History is lost on restart.

## Auto-Start (Optional)

**macOS (launchd):**
```bash
cp ~/dotfiles/bin/com.ctrlshft.hud.plist ~/Library/LaunchAgents/
# Edit the file: replace REPLACE_USERNAME with your username
launchctl load ~/Library/LaunchAgents/com.ctrlshft.hud.plist
```

**Linux (systemd):**
```bash
mkdir -p ~/.config/systemd/user/
cp ~/dotfiles/bin/ctrlshft-hud.service ~/.config/systemd/user/
systemctl --user enable --now ctrlshft-hud.service
```

Restarting the daemon clears in-memory state and re-reads from `events.jsonl`.

## Requirements

- **Node.js** — the daemon's core path has zero external dependencies
- `package.json` exists at repo root for optional `better-sqlite3` — run `npm install` for persistent history
- Without `better-sqlite3`, the daemon uses in-memory buffers + JSONL fallback (no npm install needed)
