# Reading the audit output

`audit.mjs --json` emits a `stack` field plus stack-specific blocks. Map them to phases as follows.

## `stack`

The detected stack. Read `references/phases-<stack>.md` for the phase model. If the stack is wrong, the phase model is wrong — fix detection before trusting anything.

## `totals` (all stacks)

Context only. `totalLines` is the headline number to track over time — if it isn't falling across the structural phases, the loop isn't working and something is wrong with task selection. `oversizedFileCount` is the count of files over `pageMaxLines` (300).

## `largestFiles` (all stacks)

The work queue for page/file splitting, biggest first. Always the first place to look for the next task.

## `duplicateBlocks` (all stacks)

The work queue for extraction, sorted by how many files share the block.

**Duplicate detection is deliberately crude** — sliding 15-line windows over whitespace-normalized markup. It over-reports (overlapping windows of the same block appear as several entries) and under-reports blocks that diverged slightly. Treat `duplicateBlockCount` as a trend indicator, and read the `files` list to identify what's actually shared before writing a task. Never paste the count into an issue as if it were precise.

## `astro` block

| Field | Meaning |
|---|---|
| `phase1_layouts.layoutAdoptionPct` | Exit criterion for Phase 1 (needs ≥ 90) |
| `phase1_layouts.pagesWithoutLayout` | The work queue. Batch these by head-block similarity. |
| `phase1_layouts.pagesWithRawHead` | Must reach zero. A page with a raw `<head>` isn't really using the layout even if it imports one. |
| `phase2_components.largestPages` | Work queue for page splitting, biggest first |
| `phase2_components.duplicateBlocks` | Work queue for extraction |
| `phase2_components.avgImportersPerComponent` | Below 2 means over-extraction — components nobody reuses |
| `phase2_components.orphanComponents` | Zero importers. Either wire them up or delete them. |
| `phase3_styling.tailwindWired` | Phase 3 can't start until true |
| `phase3_styling.legacyTailwindIntegration` | `@astrojs/tailwind` present — must be removed, it's the v3-era path |
| `phase3_styling.hasThemeBlock` | Tokens extracted. Do not convert components before this is true. |
| `phase3_styling.totalCssLines` | Track against the Phase 0 baseline; needs to fall ≥ 80% |
| `phase3_styling.inlineStyleCount` | Should approach zero, excluding genuinely dynamic values |

**Record the Phase 0 baseline.** `totalCssLines` is meaningless as an absolute number — the exit criterion is a reduction from where you started, so capture it before any conversion begins and keep it in the ledger's `conventions` block.

## `staticHtml` block

| Field | Meaning |
|---|---|
| `shellAdoptionPct` | Exit criterion for Phase 1 (needs ≥ 90) |
| `filesWithSharedShell` | Pages already using the shell |
| `largestFiles` | Work queue for splitting |
| `duplicateBlockCount` | Work queue for extraction |

## `workerTs` / `python` blocks

| Field | Meaning |
|---|---|
| `tsFileCount` / `pyFileCount` | Total files |
| `totalTsLines` / `totalPyLines` | Headline line count to track |
| `largestFiles` | Work queue for splitting |
| `duplicateBlockCount` | Work queue for extraction |

## Sanity checks before trusting a run

- Zero files found usually means the script ran outside the repo root, or the project uses a non-standard `srcDir`.
- A sudden jump in `layoutAdoptionPct`/`shellAdoptionPct` with no merged issue means someone did work by hand. Reconcile the ledger and say so.
- `totalLines` rising while tasks are merging means extraction is adding more boilerplate than it removes — likely components are too granular. Check `avgImportersPerComponent`.
