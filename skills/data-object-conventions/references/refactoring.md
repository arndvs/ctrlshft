# Refactoring: Extracting Data Out of a Monolithic File

Use this when a logic file has grown into a catch-all that mixes data with logic (e.g. a 400-line file holding a catalog + aliases + aggregation). The goal is a clean, one-directional split: **data in its own file, logic in the original.**

## Step 1 — Identify the seams

Separate the file's contents into:
- **Data** — static arrays, maps, lookup tables, config, constants that are pure values
- **Catalog-resolution logic** — functions that read the data to resolve/lookup (e.g. `resolveCanonicalLine`)
- **Business logic** — aggregation, computation, transformation (e.g. `aggregateInventory`)

## Step 2 — Create the data module

Create `src/lib/data/<domain>.ts` (or the repo's data location) containing:
- The data types
- The canonical data array (formatted per `formatting.md`)
- The alias/lookup maps
- Any catalog-resolution functions that are tightly coupled to the data (they read the data, so they belong with it)

Keep the data module a **leaf** — it imports nothing local.

## Step 3 — Slim the original to logic

The original file keeps only the business logic. It **imports** the data module and **re-exports** the public surface so existing consumers keep working unchanged:

```ts
// src/lib/inventory.ts (logic only)
import { INVENTORY_CATALOG, resolveCanonicalLine, type CatalogItem } from './data/inventory-catalog';

// Re-export the catalog surface so existing consumers are untouched
export { INVENTORY_CATALOG, resolveCanonicalLine };
export type { CatalogItem };

// ... aggregation logic only ...
```

## Step 4 — Preserve the public API

Before refactoring, note every symbol consumers import from the original file (search for `from './inventory'` etc.). Re-export all of them from the slimmed file so no consumer changes. This is what makes the refactor safe and atomic.

## Step 5 — Verify

- Run the test suite — all tests must pass unchanged.
- Run the type-check — re-exports must satisfy all consumers.
- Confirm the dependency arrow is one-directional: logic → data, never data → logic.

## Guardrails

- **Do not over-fragment.** A 30-line data block that is used in one place may not need extraction. Extract when there is a second consumer, non-trivial size, or a real maintainability need.
- **Do not change behavior.** This is a pure structural refactor — no logic changes, no data changes. If you find yourself changing values, stop and separate that into its own change.
- **Do not duplicate.** After extraction, delete the data from the original file. Never keep two copies.
- **Keep it atomic.** Commit the extraction as one logical change (see `atomic-commits`).
