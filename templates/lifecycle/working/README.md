# working/

Scratch and execution workspace for in-progress tasks. See [ARTIFACT-LIFECYCLE.md](../docs/ARTIFACT-LIFECYCLE.md) for the full lifecycle specification.

## Tracked lanes (committed to git)

| Directory | Purpose | Lifecycle |
|-----------|---------|-----------|
| `active/` | Execution plans for in-progress work | Delete when work ships |
| `refs/` | Reference pointers and third-party material | Delete when consumed |
| `research/` | Synthesized exploration artifacts | Delete when done; promote to `docs/research/` if durable |

## Ignored lanes (gitignored)

| Directory | Purpose |
|-----------|---------|
| `runtime/` | Auto-generated state files |
| `tmp/` | Temporary task artifacts |
| `logs/` | Execution and event logs |

## Rules

- No loose files in this directory root — use the appropriate subdirectory.
- Agent-useful markdown must be in tracked lanes, not ignored ones.
- Never blanket-ignore `working/` — ignore specific subdirectories only.
