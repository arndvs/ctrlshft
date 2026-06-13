# Artifact Lifecycle

How files move through this project — from raw reference material to permanent documentation or deletion.

> **Based on the [ctrl+shft artifact lifecycle](https://github.com/arndvs/ctrlshft).** Adjust directories and conventions to fit your project.

---

## Lifecycle Flow

```
refs → research → active plan → ship
                                  ├── docs/adr/       (decisions)
                                  ├── docs/research/   (durable synthesis)
                                  ├── docs/audits/     (assessment artifacts)
                                  ├── GitHub Issues     (issue slices)
                                  └── delete            (everything else)
```

## Directory Map

### `working/` — Scratch and Execution

| Directory | Tracked | Purpose | Lifecycle |
|-----------|---------|---------|-----------|
| `working/active/` | Yes | Execution plans for in-progress work | Delete when work ships |
| `working/refs/` | Yes | Reference pointers and third-party material | Delete when consumed |
| `working/research/` | Yes | Synthesized exploration artifacts | Delete when done; promote if durable |
| `working/runtime/` | No | Auto-generated state files | Ignored |
| `working/tmp/` | No | Temporary task artifacts | Ignored |
| `working/logs/` | No | Execution and event logs | Ignored |

### `plans/` — PRDs and Issue Breakdowns

| Directory | Purpose | Lifecycle |
|-----------|---------|-----------|
| `plans/` | PRD documents | Archive or delete after work completes |
| `plans/issues/` | Issue slice breakdowns | Delete after issues are created |

### `docs/` — Permanent Documentation

| Directory | Purpose |
|-----------|---------|
| `docs/adr/` | Architecture Decision Records |
| `docs/reference/` | Durable reference material |
| `docs/research/` | Promoted research with lasting value |
| `docs/audits/` | Dated assessment artifacts |

---

## Rules

- **No loose files** in `working/` root — use the appropriate subdirectory.
- **Never blanket-ignore** `working/` — ignore specific runtime subdirectories only.
- **Refs need provenance** — Source URL, date fetched, and context for why it was collected.
- **Delete when done** — plans, refs, and research are disposable. Only promote to `docs/` when the work has lasting value.
