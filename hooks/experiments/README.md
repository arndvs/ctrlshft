# hooks/experiments/

Experimental hooks for feature discovery. Not wired into bootstrap or settings.
Each script documents its own setup and teardown instructions.

Scripts here are probes — they write logs, dump state, or test undocumented behavior.
Delete logs from `~/.claude/experiments/` after experiments complete.

## Active experiments

| Script | Purpose | Status |
|--------|---------|--------|
| `statusline-probe.sh` | Discover how `context_window.used_percentage` is delivered to statusLine commands | Pending |

## What to do with results

| Found in | Implementation for `context-warning.sh` |
|----------|----------------------------------------|
| stdin as JSON | `USED_PCT=$(echo "$STDIN" \| jq -r '.context_window.used_percentage // 0')` |
| env var | `USED_PCT="${CONTEXT_WINDOW_USED_PERCENTAGE:-0}"` (or whatever the var name is) |
| CLI arg | `USED_PCT="${1:-0}"` |
| Not found | statusLine bridge doesn't work — graduated warnings not feasible via this path |
