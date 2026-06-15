---
description: "Resource management — prevent memory leaks, handle leaks, and unbounded growth in JS/TS code."
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs}"
---

# Resource Management

Each section is tagged: `[PROD]` = production hazard (affects deployed app), `[DEV]` = dev-mode hazard (HMR/DX), `[BOTH]` = both. Fix patterns are mandatory — flagging without a correct fix is not useful.

---

## Module-scope state `[BOTH]`

All mutable module-scope state must satisfy two requirements:

1. **Bounded** — has eviction, TTL, or max size (production safety)
2. **HMR-safe** — attached to `globalThis` so it survives hot reload (dev safety)

Immutable frozen constants and `as const` objects are exempt — they don't grow and their duplication is negligible.

```typescript
// ✗ WRONG — unbounded, not HMR-safe
const cache = new Map<string, Data>();

// ✗ STILL WRONG — bounded but duplicated on every HMR cycle
const cache = new LRUCache<string, Data>({ max: 500 });

// ✓ RIGHT — bounded AND HMR-safe
declare global { var __myCache: LRUCache<string, Data> | undefined; }
const cache = (globalThis.__myCache ??= new LRUCache<string, Data>({ max: 500 }));
```

Decision tree for module-scope state:

1. Is it immutable/frozen (`as const`, `Object.freeze`)? → Module scope is fine, no action needed.
2. Is it mutable/stateful? → Must use `globalThis.__x ??=` pattern AND have bounded size.
3. Is it large data (100+ entries)? → See "Large static data" section below.
4. Is it an SDK client? → See "SDK singletons" section below.

## Large static data at module scope `[DEV]`

Large inline datasets (hundreds of records, thousands of lines) as module-scope constants are re-allocated on every HMR cycle. The old copy is retained by the bundler's module cache. In production this is fine — the module evaluates once. In dev it leaks megabytes per save.

**The fix is NOT to delete the data.** The fix is to change HOW the data loads so HMR doesn't re-allocate it:

```typescript
// ✗ WRONG — 3,000 objects re-allocated on every HMR cycle in dev
export const reviews: Review[] = [{ id: "1", ... }, /* 3,000 more */];

// ✓ RIGHT — extract to JSON, lazy-load with globalThis cache
declare global { var __reviews: Review[] | undefined; }

export function getReviews(): Review[] {
  return (globalThis.__reviews ??= JSON.parse(
    readFileSync(join(process.cwd(), "data/reviews.json"), "utf-8")
  ));
}

// ✓ RIGHT — async variant for Edge runtime (no fs module)
declare global { var __reviews: Review[] | undefined; }

export async function getReviews(): Promise<Review[]> {
  if (globalThis.__reviews) return globalThis.__reviews;
  const mod = await import("@/data/reviews.json");
  return (globalThis.__reviews = mod.default);
}

// ✓ ALSO RIGHT — JSON import (bundler treats as static asset, not re-executed code)
import reviews from "./data/reviews.json";
```

**Invalid fixes** — these look like they address the problem but don't:
- Wrapping in a function without `globalThis` (still module-scope `let`, still duplicated on HMR)
- Moving to a separate `.ts` file with `export const` (same problem, different file)
- Deleting the data (masks the problem, loses functionality)
- Adding `as const` (irrelevant to allocation)

## SDK and client singletons `[BOTH]`

Third-party SDK clients (analytics, monitoring, database, email) must be created once AND be HMR-safe. Each instance allocates internal queues, timers, and connection pools that may not fully clean up on `shutdown()`.

```typescript
// ✗ WRONG — new instance per request (PROD leak)
function track(event: string) {
  const client = new AnalyticsSDK(key);
  client.capture(event);
  client.shutdown();
}

// ✗ WRONG — singleton but duplicated on HMR (DEV leak)
const client = new AnalyticsSDK(key);

// ✓ RIGHT — HMR-safe singleton
declare global { var __analytics: AnalyticsSDK | undefined; }
const client = (globalThis.__analytics ??= new AnalyticsSDK(key));

export function track(event: string) {
  client.capture(event);
}
```

---

## Lifecycle cleanup `[PROD]`

### Event listeners

Every `addEventListener`, `.on()`, `.subscribe()`, or `.observe()` must have corresponding removal. Prefer `AbortController.signal` — it handles multiple listeners in one cleanup call:

```typescript
// ✗ WRONG — no cleanup
useEffect(() => {
  window.addEventListener("resize", handleResize);
  window.addEventListener("scroll", handleScroll);
}, []);

// ✓ RIGHT — AbortController cleans up all listeners at once
useEffect(() => {
  const controller = new AbortController();
  window.addEventListener("resize", handleResize, { signal: controller.signal });
  window.addEventListener("scroll", handleScroll, { signal: controller.signal });
  return () => controller.abort();
}, []);
```

For `IntersectionObserver`, `MutationObserver`, `ResizeObserver` — call `.disconnect()` in cleanup:

```typescript
useEffect(() => {
  const observer = new IntersectionObserver(callback, options);
  observer.observe(ref.current);
  return () => observer.disconnect();
}, []);
```

### Timers

Every `setInterval` must have `clearInterval` in cleanup. Every `requestAnimationFrame` must have `cancelAnimationFrame`:

```typescript
// ✓ RIGHT — interval with cleanup
useEffect(() => {
  const id = setInterval(poll, 5000);
  return () => clearInterval(id);
}, []);

// ✓ RIGHT — animation frame with cleanup
useEffect(() => {
  let rafId: number;
  function animate() { /* ... */ rafId = requestAnimationFrame(animate); }
  rafId = requestAnimationFrame(animate);
  return () => cancelAnimationFrame(rafId);
}, []);
```

### Abort controllers

Every `fetch()` in a React component must use `AbortController`. Guard `setState` calls against abort:

```typescript
useEffect(() => {
  const controller = new AbortController();

  async function load() {
    try {
      const res = await fetch(url, { signal: controller.signal });
      const data = await res.json();
      if (!controller.signal.aborted) setData(data);
    } catch (e) {
      if (e instanceof DOMException && e.name === "AbortError") return;
      throw e;
    }
  }
  load();

  return () => controller.abort();
}, [url]);
```

### React effects

`useEffect` that creates any resource (subscription, listener, timer, observer, fetch) must return a cleanup function. Cancel in-flight work on unmount to avoid wasted computation and stale state updates — use `AbortController`, not mounted-ref checks.

```typescript
// ✓ Composing multiple cleanups in one effect
useEffect(() => {
  const controller = new AbortController();
  const intervalId = setInterval(poll, 5000);
  window.addEventListener("focus", onFocus, { signal: controller.signal });

  return () => {
    controller.abort();
    clearInterval(intervalId);
  };
}, []);
```

---

## Bounded collections `[PROD]`

### Caches

In-memory caches must have TTL, max size, or LRU eviction. A `Map` without bounds is a leak by design. Consider `WeakMap` when keys are objects that should be GC-eligible:

```typescript
// ✗ WRONG — unbounded, grows forever
const cache = new Map<string, Result>();

// ✓ RIGHT — WeakMap (GC'd when keys are unreferenced)
const cache = new WeakMap<object, Result>();

// ✓ RIGHT — LRU with max size (combine with globalThis for HMR safety)
declare global { var __resultCache: LRUCache<string, Result> | undefined; }
const cache = (globalThis.__resultCache ??= new LRUCache<string, Result>({ max: 200, ttl: 1000 * 60 * 5 }));
```

### SSE and WebSocket consumers

Listeners that buffer incoming messages must bound the buffer. Accumulating without limits grows memory linearly with uptime:

```typescript
// ✗ WRONG — unbounded accumulation
const messages: Message[] = [];
eventSource.onmessage = (e) => {
  messages.push(JSON.parse(e.data));
};

// ✓ RIGHT — sliding window (keep last N)
const MAX_MESSAGES = 1000;
const messages: Message[] = [];
eventSource.onmessage = (e) => {
  messages.push(JSON.parse(e.data));
  if (messages.length > MAX_MESSAGES) messages.splice(0, messages.length - MAX_MESSAGES);
};

// ✓ RIGHT — process and discard (don't accumulate)
eventSource.onmessage = (e) => {
  processMessage(JSON.parse(e.data));
};
```

---

## Reference retention `[PROD]`

### Closures

Closures that capture large objects (DOM nodes, datasets, response bodies) in long-lived callbacks prevent GC of the entire captured scope. Extract only the values needed:

```typescript
// ✗ WRONG — closure retains entire response (could be megabytes)
const callback = () => { console.log(response.data.items.length); };
longLivedEmitter.on("check", callback);

// ✓ RIGHT — extract the value, let response be GC'd
const itemCount = response.data.items.length;
const callback = () => { console.log(itemCount); };
longLivedEmitter.on("check", callback);
```

---

## I/O resources `[PROD]`

### Streams and connections

Database connections, file handles, readable streams, and WebSocket connections must be closed in all code paths — including error paths. Use `try/finally`, or `using` (TC39 Explicit Resource Management) when available:

```typescript
// ✓ RIGHT — try/finally
const file = await open(path);
try {
  // ... use file
} finally {
  await file.close();
}

// ✓ RIGHT — TC39 explicit resource management
await using file = await open(path);
// file.close() called automatically at block exit

// ✓ RIGHT — database: use pool (don't open/close per query)
const result = await pool.query("SELECT ...");
```

---

## Build-time `[DEV]`

### Conditional build plugins

Build plugins (Sentry, bundle analyzers, coverage tools) should not load in dev unless explicitly needed:

```typescript
// ✗ WRONG — Sentry SDK imported in dev even though it's disabled
export default withSentryConfig(nextConfig, sentryOptions);

// ✓ RIGHT — only wrap in production
const finalConfig = process.env.NODE_ENV === "production"
  ? withSentryConfig(nextConfig, sentryOptions)
  : nextConfig;
export default finalConfig;
```

### Console logging in hot paths `[DEV]`

Do not `console.log` large objects in hot paths (middleware, render functions, event handlers). Serialization creates a full string copy retained by the console buffer:

```typescript
// ✗ WRONG — serializes entire request body on every request
app.use((req, res, next) => { console.log("Request:", req.body); next(); });

// ✓ RIGHT — log only identifiers
app.use((req, res, next) => {
  console.log(`${req.method} ${req.url} [${req.headers["content-length"] ?? 0}b]`);
  next();
});
```
