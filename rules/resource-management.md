---
description: "Resource management — prevent memory leaks, handle leaks, and unbounded growth in JS/TS code."
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs}"
---

# Resource Management

## Event listeners

Every `addEventListener`, `.on()`, `.subscribe()`, or `observe()` must have a corresponding removal in the same scope's cleanup path (`removeEventListener`, `.off()`, `.unsubscribe()`, `disconnect()`). In React, this means the `useEffect` return function. In vanilla JS, this means a `destroy()` or `cleanup()` method.

## Timers

Every `setInterval` must have a corresponding `clearInterval` in the cleanup path. `setTimeout` inside loops or recurring patterns must also be cleared. Never create intervals without storing the ID.

## Abort controllers

Long-lived or user-cancellable `fetch()` calls must use `AbortController`. In React components, abort in the `useEffect` cleanup. In server code, abort on request cancellation.

## Module-scope mutability

Do not declare mutable data structures (`Map`, `Set`, `Array`, plain objects used as accumulators) at module scope unless they have a bounded size or explicit eviction. Module-scope state persists across requests in server runtimes and across HMR in dev mode.

```typescript
// ✗ WRONG — grows unbounded across requests
const cache = new Map<string, Data>();

// ✓ RIGHT — bounded with eviction
const cache = new LRUCache<string, Data>({ max: 500 });

// ✓ RIGHT — framework-managed cache
import { unstable_cacheLife as cacheLife } from "next/cache";
```

## Streams and connections

Database connections, file handles, readable streams, and WebSocket connections must be closed in all code paths — including error paths. Use `try/finally` or `using` (TC39 Explicit Resource Management) when available.

```typescript
// ✓ RIGHT
const file = await open(path);
try {
  // ... use file
} finally {
  await file.close();
}
```

## React effects

- `useEffect` that creates subscriptions, listeners, timers, or observers must return a cleanup function
- `useEffect` that fetches data should use `AbortController` and check a cancelled flag before setting state
- Never `setState` on an unmounted component — the cleanup function must prevent this

## Closures

Avoid closures that capture large objects (DOM nodes, datasets, response bodies) in long-lived callbacks. Extract only the primitive values needed.

## Caches

In-memory caches must have one of: TTL, max size, or LRU eviction. A `Map` used as a cache without bounds is a memory leak by design.
