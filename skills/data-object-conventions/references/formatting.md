# Formatting Rules for Data Objects

The single most important rule: **write full object literals, one property per line.** This is what makes data files readable, greppable, and diff-friendly.

## 1. One object per entry, one property per line

Every entry in a data array is a full object literal. Every property is on its own line.

```ts
// ✅ GOOD — full object, one property per line
export const products: readonly Product[] = [
  {
    sku: 'MCR-MAGIC2',
    name: 'Focus 2.0',
    imageUrl: '/images/products/focus-transparent.png',
    storefronts: ['main'],
    active: true,
  },
  {
    sku: 'MCR-SERENITY',
    name: 'Serenity Capsules',
    imageUrl: 'https://mcrdse.shop/images/products/awaken/serenity-daily-front.png',
    storefronts: ['shop'],
    active: true,
  },
];
```

```ts
// ❌ BAD — compact factory calls hide the data behind positional args
export const INVENTORY_CATALOG = [
  main('MCR-MAGIC2', 'Focus 2.0', '/images/products/focus-transparent.png'),
  shop('MCR-SERENITY', 'Serenity Capsules', 'https://mcrdse.shop/...'),
];
```

```ts
// ❌ BAD — single-line objects are hard to scan and diff
export const products = [
  { sku: 'MCR-MAGIC2', name: 'Focus 2.0', imageUrl: '/img.png', storefronts: ['main'], active: true },
];
```

## 2. No factory helpers that obscure data

Factory functions (`main()`, `shop()`, `catalog()`) that collapse several fields into positional arguments make the data unreadable. If you need to express a repeated pattern (like a storefront), make it an **explicit field** on the object, not a factory call.

- ✅ `storefronts: ['main', 'shop']` — explicit, greppable
- ❌ `shared('SKU', 'Name', '/img.png')` — the reader must find the factory to know what `shared` means

## 3. Explicit fields, no hidden defaults

Every field is spelled out. Do not rely on a factory's default parameter to imply a value.

```ts
// ✅ GOOD — active is explicit
{ sku: 'MCR-FOCUS', name: 'Focus Dose', active: false }

// ❌ BAD — active is implied by which factory was called
retired('MCR-FOCUS', 'Focus Dose', '/img.png')
```

## 4. Property ordering

Keep a consistent property order across all entries in a file. Convention:

1. **Identity** — `id` / `sku` / `key` first
2. **Display** — `name` / `title` / `label`
3. **Content** — `description`, `imageUrl`, etc.
4. **Classification** — `category`, `type`, `storefronts`, `status`
5. **Optional/derived** — `featured`, `badge`, etc. last

Consistent ordering makes entries visually parallel and easy to diff.

## 5. String literals

- Use single quotes for strings (matching the repo's TS convention).
- Use double quotes only if the string contains a single quote.
- Keep URLs and paths as plain strings; do not wrap in template literals unless interpolating.

## 6. Arrays of primitives

Keep short primitive arrays inline on one line when they fit:

```ts
{ storefronts: ['main', 'shop'] }
```

For long arrays, break each element onto its own line:

```ts
{
  idealFor: [
    'New mothers 1-12 weeks postpartum',
    'Recovery support',
    'Stress relief',
  ],
}
```

## 7. Trailing commas

Always use trailing commas in multi-line object literals and arrays. This produces clean diffs when adding entries.

## 8. Comments

- Use a brief comment above a data array to state its purpose and any invariants (e.g. "active sheet must stay 36 units").
- Use section comments to group related entries (e.g. `// mcrdse.com`, `// mcrdse.shop`).
- Do NOT comment every line — the object literals should be self-documenting.
