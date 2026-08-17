---
name: data-object-conventions
description: >
  Enforce consistent structure, formatting, and placement for static data
  objects (catalogs, config, content, lookup tables, enums-as-data) in
  TypeScript/JavaScript codebases. Use whenever creating, editing, refactoring,
  or reviewing a data file or data object — including extracting data out of
  logic files, splitting a monolithic file, deciding where data should live,
  or formatting a data array. Triggers on phrases like 'data file', 'data
  object', 'catalog', 'lookup table', 'extract the data', 'split this file',
  'format this data', 'where should this data live', 'this data is ugly'.
  Do NOT use for runtime state, API responses, or database rows — those are
  data-in-motion, not static data.
---

# Data Object Conventions

Output "Read Data Object Conventions skill." to chat to acknowledge you read this file.

Enforces a single, consistent way to structure, format, and place **static data objects** in TS/JS codebases, so data files are readable, greppable, and maintainable instead of dense one-liners.

## When to use

Use when you are **creating, editing, refactoring, or reviewing** a static data object or data file. This includes extracting data out of a logic file, splitting a monolithic catch-all, deciding where data should live, or reformatting an existing data array. Do NOT use for runtime state, API responses, or DB rows.

## Core rules (the non-negotiables)

1. **Data lives in its own file** — never inline static data inside logic, components, or API handlers. Extract to a dedicated data module.
2. **One file per data domain** — a catalog, a lookup table, a config set each get their own file, named after the domain.
3. **Type + data co-located** — each data file defines its exported type immediately above the data it describes.
4. **One object per entry, one property per line** — write full object literals, never compact factory calls or single-line objects. This is the #1 readability rule.
5. **Explicit fields, no magic** — every field is spelled out. No positional args, no hidden defaults, no factory helpers that obscure the data.
6. **Derived views exported alongside canonical data** — if consumers need subsets/derived forms, export them as named constants derived from the canonical list.
7. **`readonly` for immutable data** — mark exported arrays/objects `as const` or `readonly` where the data must not be mutated.

## Workflow

1. **Identify the data** — is it static (catalog, config, content, lookup) or in-motion (state, API, DB)? Only static data follows this skill.
2. **Place it** — create `src/lib/data/<domain>.ts` (or the repo's established data location). See `references/placement.md`.
3. **Type it** — define the exported type, then the typed array.
4. **Format it** — full object literals, one property per line. See `references/formatting.md`.
5. **Export derived views** — add named derived constants if consumers need them.
6. **Wire consumers** — import the typed data; never re-derive or duplicate it.

## Formatting example (the target)

```ts
// src/lib/data/massage-types-data.ts
export type MassageType = {
  id: string;
  title: string;
  category: 'prenatal' | 'postpartum' | 'therapeutic';
  duration: string;
  priceRange: string;
  featured?: boolean;
};

export const massageTypes: readonly MassageType[] = [
  {
    id: 'prenatal-wellness',
    title: 'Prenatal Wellness Massage',
    category: 'prenatal',
    duration: '60-90 min',
    priceRange: '$129-$179',
    featured: true,
  },
  {
    id: 'postpartum-renewal',
    title: 'Postpartum Renewal Massage',
    category: 'postpartum',
    duration: '60-90 min',
    priceRange: '$119-$169',
  },
];
```

## Anti-patterns (what this skill forbids)

| Anti-pattern | Problem | Fix |
|---|---|---|
| Compact factory calls: `main('SKU', 'Name', '/img.png')` | Hides data behind positional args; unreadable | Full object literal, one property per line |
| Single-line objects: `{ id: 'x', name: 'y' }` | Hard to scan/diff | One property per line |
| Inline data in logic/component | Mixes concerns, not reusable | Extract to a data file |
| `utils.ts` / `data.ts` catch-alls | Impossible to navigate | One domain per file |
| Duplicated data across files | Drift (e.g. payment-method lists) | Single source of truth + derived exports |
| Magic numbers/strings inline | No meaning | Named constants or typed fields |

## References

- `references/formatting.md` — full formatting rules with before/after examples
- `references/placement.md` — where data files live, naming, folder-per-domain
- `references/derived-and-types.md` — typing, derived views, readonly, enums-as-data
- `references/refactoring.md` — how to extract data out of a monolithic file safely
- `references/checklist.md` — quick review checklist for data files

## Related skills

- `frontend-component-style` — owns the four-layer split (data/logic/primitive/composed) for UI components; this skill owns the *formatting and structure of the data files themselves*.
- `typescript-conventions` — owns TS typing patterns; this skill applies them to data objects.
