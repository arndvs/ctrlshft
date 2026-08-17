# Placement: Where Data Files Live

## 1. A dedicated `data/` directory

Static data lives in a dedicated directory, conventionally `src/lib/data/` (or the repo's established data location). This separates data from logic and gives it a discoverable home.

```
src/lib/
├── data/                 ← static data lives here
│   ├── inventory-catalog.ts
│   ├── payment-methods.ts
│   └── massage-types-data.ts
├── inventory.ts          ← logic imports from data/
└── inventory-service.ts
```

If the repo already has a data location (e.g. `src/lib/_generated/` for generated data, or a `content/` folder), use that instead of inventing a new one. Match the existing convention.

## 2. One file per data domain

Each data domain gets its own file, named after the domain. A catalog, a lookup table, a config set, a content collection each get their own file.

- ✅ `inventory-catalog.ts`, `payment-methods.ts`, `insurance-providers.ts`, `team-data.ts`
- ❌ `data.ts`, `utils.ts`, `constants.ts` — catch-alls that mix unrelated domains

## 3. Naming

- **kebab-case** filenames, `.ts` extension.
- Name the file after the **domain** it holds, not where it's used.
- Common suffixes: `-data.ts` (content collections), `-catalog.ts` (product/SKU catalogs), `-providers.ts` / `-methods.ts` (lookup tables), `-config.ts` (configuration).
- The exported array/constant is named after the domain in PascalCase or UPPER_SNAKE as appropriate (e.g. `INVENTORY_CATALOG`, `massageTypes`, `INSURANCE_PROVIDERS`).

## 4. Folder-per-complex-domain

If a domain is large and has multiple concerns (types, defaults, per-page data), use a folder with an `index.ts` re-export:

```
src/lib/data/specialties-data/
├── index.ts       ← re-exports the public surface
├── types.ts       ← shared types
├── defaults.ts    ← default values
└── pages/         ← per-page data
```

The `index.ts` re-exports everything so consumers import from the folder root. Keep a deprecated shim only if backward compatibility is required.

## 5. Data files import nothing local

A data file should be a **leaf** — it imports no local modules (only types from `types/` if needed). It exports typed data. This keeps the dependency arrow one-directional: logic → data, never data → logic.

## 6. What does NOT belong in a data file

- **Runtime state** — current balances, in-memory caches, request-scoped values
- **API responses / DB rows** — data-in-motion, not static data
- **Business logic** — functions that compute, transform, or validate (those go in logic files)
- **Secrets / credentials** — never in data files (see `env-security` rules)

If a value changes at runtime or is fetched, it is not static data and does not follow this skill.
