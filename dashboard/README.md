# Compliance Dashboard

> **Note:** The dashboard has been renamed to **HUD**. See [`hud/README.md`](../hud/README.md) for the current documentation.

## Quick Start

```bash
ctrl dashboard
# Visit http://localhost:7823
```

The active daemon is `bin/start-hud.sh`. The `ctrl dashboard` CLI routes to it automatically.

## Lifecycle Commands

| Command | What it does |
|---------|-------------|
| `ctrl dashboard` | Start daemon (default, background) |
| `ctrl dashboard stop` | Stop daemon |
| `ctrl dashboard status` | Check if running, show PID and URL |
| `ctrl dashboard restart` | Stop + start |
| `ctrl dashboard logs [-f]` | Show daemon log |
| `bash ~/dotfiles/bin/start-hud.sh foreground` | Run in foreground (no daemonization) |

Port defaults to `7823`. Override with `HUD_PORT=8080 ctrl dashboard`.

## Architecture

```
Agent session
  │
  ├── hooks (secret-guard, compaction-guard, etc.)
  ├── skills (do-work, compliance-audit, etc.)
  └── detect-context.sh
        │
        ▼
write-dashboard-state.sh ──→ Transport priority:
        │                       1. Named pipe (dashboard.pipe)
        │                       2. HTTP POST to daemon (:7823/api/event)
        │                       3. JSONL append (working/events.jsonl)
        ▼
dashboard-daemon.js
  ├── Reads events.jsonl on startup
  ├── Watches for new events (1s poll)
  ├── Persists state to working/dashboard-state.json
  └── Serves HTTP API
        │
        ▼
dashboard/index.html
  └── Polls GET /api/state every 5 seconds
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | Serves the dashboard UI (`dashboard/index.html`) |
| GET | `/api/state` | Returns current compliance state as JSON |
| POST | `/api/event` | Receives compliance events (JSON body) |
| GET | `/healthz` | Health check — returns `{ "ok": true, "uptime": ... }` |

## Event Types

Events emitted by `write-dashboard-state.sh`:

| Type | Source | Description |
|------|--------|-------------|
| `context` | `detect-context.sh` | Active project contexts (nextjs, sanity, etc.) |
| `info` | Various | Informational messages |
| `read` | Skill loading | "Read X skill" acknowledgement |
| `compliance-result` | `compliance-audit` | Full compliance audit result |
| `pass` | Rule check | Rule compliance passed |
| `fail` | Rule check | Rule compliance failed |
| `warn` | Rule check | Rule compliance warning |

## Data Persistence

All runtime data lives in `working/` (gitignored):

- `working/events.jsonl` — append-only event log
- `working/dashboard-state.json` — current aggregated state
- `working/dashboard-daemon.pid` — daemon PID file
- `working/dashboard-daemon.log` — daemon stdout/stderr log

Restarting the daemon clears in-memory state and re-reads from `events.jsonl`.

## Requirements

- **Node.js** — the daemon is a zero-dependency Node.js HTTP server
- No npm install needed — no `node_modules`, no `package.json`
