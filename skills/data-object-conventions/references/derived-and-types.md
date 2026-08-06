# Types, Derived Views, and Enums-as-Data

## 1. Type + data co-located

Each data file defines its exported type immediately above the data it describes. The type documents the shape; the typed array enforces it.

```ts
export type Product = {
  sku: string;
  name: string;
  imageUrl: string;
  storefronts: InventoryStorefront[];
  active: boolean;
};

export const products: readonly Product[] = [ /* ... */ ];
```

For complex domains with many types, split types into a `types.ts` within the domain folder and re-export from `index.ts`. For a single-domain file, co-locating the type is preferred.

## 2. `readonly` and `as const` for immutable data

Static data should not be mutated. Mark exported arrays and objects appropriately:

```ts
// Array of objects — readonly array, mutable objects (or use as const for full immutability)
export const products: readonly Product[] = [ /* ... */ ];

// Primitive lookup — as const for a literal union
export const PAYMENT_METHODS = ['cashapp', 'venmo', 'zelle'] as const;
export type PaymentMethod = (typeof PAYMENT_METHODS)[number];
```

Use `as const` when you want the literal values to be the type (e.g. deriving a union type). Use `readonly` when you want to prevent reassignment of the array but keep the object type.

## 3. Derived views exported alongside canonical data

When consumers need subsets or derived forms, export them as **named constants derived from the canonical list** — never as separate hand-maintained copies.

```ts
export const INSURANCE_PROVIDERS: readonly InsuranceProvider[] = [ /* ... */ ];

// Derived views — all derive from the canonical list, so they cannot drift
export const INSURANCE_PROVIDER_NAMES: string[] = INSURANCE_PROVIDERS.map((p) => p.name);
export const INSURANCE_PROVIDERS_COMMA_SEPARATED: string = INSURANCE_PROVIDER_NAMES.join(', ');
export const INSURANCE_PROVIDERS_SHORT: string[] = INSURANCE_PROVIDER_NAMES.slice(0, 4);
```

This is the fix for the "duplicated data across files" anti-pattern: one canonical source, derived views computed from it.

## 4. Enums-as-data

Prefer a typed const array + derived union type over a TS `enum` for static lookup data:

```ts
// ✅ GOOD — data-driven, greppable, easy to extend
export const INVENTORY_STOREFRONTS = ['main', 'shop', 'gift', 'legacy'] as const;
export type InventoryStorefront = (typeof INVENTORY_STOREFRONTS)[number];

// ❌ AVOID — TS enum is opaque, harder to grep, and not data
// export enum InventoryStorefront { Main = 'main', Shop = 'shop' }
```

## 5. Lookup tables

For key→value lookups, use a typed `Record` or a `Map` built from the canonical array:

```ts
// From a canonical array
export const CATALOG_BY_SKU = new Map(INVENTORY_CATALOG.map((item) => [item.sku, item]));

// Or a typed record for a small fixed set
export const STOREFRONT_LABEL: Record<InventoryStorefront, string> = {
  main: 'mcrdse.com',
  shop: 'mcrdse.shop',
  gift: 'Free gift',
  legacy: 'Legacy',
};
```

Build lookup maps from the canonical data so they stay in sync.

## 6. Optional fields

Use optional fields (`?`) for data that is genuinely absent in some entries. Do not use `null`/`undefined` placeholders for fields that are always present — make them required.

```ts
export type Product = {
  sku: string;
  name: string;
  imageUrl: string;
  featured?: boolean;   // only some products are featured
};
```
