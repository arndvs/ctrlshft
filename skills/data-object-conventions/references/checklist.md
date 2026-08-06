# Data File Review Checklist

Run this when creating, editing, or reviewing a static data file.

## Structure & placement

- [ ] Data lives in a dedicated data file (not inline in logic/component/API handler)
- [ ] File is in the repo's data location (`src/lib/data/` or established equivalent)
- [ ] One domain per file — no catch-all `data.ts` / `utils.ts`
- [ ] Filename is kebab-case, named after the domain
- [ ] Data file is a leaf — imports nothing local

## Formatting

- [ ] Full object literals — one object per entry, one property per line
- [ ] No factory helpers obscuring data (no `main('SKU', 'Name', '/img')`)
- [ ] No single-line objects
- [ ] Every field explicit — no hidden defaults
- [ ] Consistent property order across entries (identity → display → content → classification → optional)
- [ ] Trailing commas on multi-line literals
- [ ] Section comments group related entries; no per-line noise

## Types & derived views

- [ ] Exported type defined immediately above the data
- [ ] Array typed (`readonly Product[]` or `as const` as appropriate)
- [ ] Derived views computed from canonical data, not hand-maintained copies
- [ ] Lookup maps built from canonical data
- [ ] Enums-as-data (const array + union type), not TS `enum`

## Correctness

- [ ] No duplicated data across files (single source of truth)
- [ ] No secrets / credentials in the data file
- [ ] No runtime state, API responses, or DB rows (those are data-in-motion)
- [ ] No behavior change if this was a refactor — data values identical to before

## Verification (after a refactor)

- [ ] Test suite passes unchanged
- [ ] Type-check passes
- [ ] Public API re-exported so consumers are untouched
- [ ] Dependency arrow is one-directional (logic → data)
