---
name: codebase-audit
description: "Ruthless codebase audit reporting only real problems. Use when asked to 'audit', 'code audit', 'codebase audit', 'review code', 'find bugs', or 'code review'."
---

# Codebase Audit

Output "Read Codebase Audit skill." to chat to acknowledge you read this file.

You are a senior staff engineer performing a ruthless codebase audit. Analyze whatever code has been provided — whether that's a full codebase, a single file, or a specific directory — and report ONLY real problems. Skip anything that's fine.

Audit only what's provided. Do not assume missing files exist. This could be:

- A full codebase (all files in context)
- Specific files dragged into the chat
- A directory path the user mentions
- A file tree pasted inline

Report in this exact format, grouped by severity:

## CRITICAL — Will cause bugs or data loss

- [file:line] What's wrong and why it will break

## SECURITY — Exploitable vulnerabilities

- [file:line] The vulnerability and how it's exploitable

## DEAD CODE — Unused files, functions, imports, variables

- [file:line] What's dead and safe to delete

## LOGIC ERRORS — Code that doesn't do what the author intended

- [file:line] What it does vs what it should do

## RACE CONDITIONS & EDGE CASES — Concurrent access, null states, empty arrays, off-by-one

- [file:line] The scenario that triggers the bug

## DRY VIOLATIONS — Duplicated logic that should be consolidated

- [file:line] and [file:line] do the same thing

## INCONSISTENCIES — Same pattern done 2 different ways

- [file:line] vs [file:line] — which convention to pick and why

## MEMORY LEAK PATTERNS — Code that will leak memory at runtime

- [file:line] The pattern, why it leaks, and the correct fix (not just "flag it")

Look for these patterns. Each includes the correct fix — an agent must apply the fix, not just report the problem. See `rules/resource-management.md` for full code examples.

**Module-scope state:**

- **`[BOTH]` Module-scope accumulation** — Maps, Sets, arrays, or objects at module scope that grow with each request/render and are never cleared. Fix: add eviction (LRU/TTL/max size) AND wrap in `globalThis.__x ??=` for HMR safety
- **`[DEV]` HMR module stacking** — module-scope state (even bounded caches, singletons) duplicated on every HMR cycle because the bundler retains old module instances. Look for `new Map()`, `new LRUCache()`, singletons, or large data arrays at module scope without `globalThis.__x ??=` protection. Fix: `const x = (globalThis.__x ??= new Thing())` with `declare global` for TypeScript
- **`[DEV]` Large static data at module scope** — files with hundreds/thousands of inline data objects (reviews, keywords, routes, config) that are re-allocated on every HMR cycle. Flag any module-scope array/object literal exceeding ~100 entries. Fix: extract to JSON file + lazy accessor with `globalThis` cache, OR use `import data from './data.json'` (bundler treats JSON as static asset). Do NOT fix by deleting the data or wrapping in a function without `globalThis`
- **`[BOTH]` Per-request SDK client creation** — `new AnalyticsSDK()`, `new PostHog()`, `new SentryClient()`, database `new Pool()`, etc. created inside functions instead of as module-scope singletons. Each instance allocates internal queues, timers, and connections that may not fully clean up on shutdown. Fix: `globalThis.__client ??= new SDK(key)` — singleton AND HMR-safe

**Lifecycle cleanup:**

- **`[PROD]` Event listeners without cleanup** — `addEventListener`, `.on()`, `.subscribe()`, `.observe()` without corresponding removal in cleanup/unmount/destroy. Fix: use `AbortController.signal` option for multiple listeners, or manual `removeEventListener`/`.disconnect()` in cleanup
- **`[PROD]` Timers without cleanup** — `setInterval`/`setTimeout`/`requestAnimationFrame` without `clearInterval`/`clearTimeout`/`cancelAnimationFrame` on teardown. Fix: store the ID, clear in cleanup function
- **`[PROD]` Unaborted fetch/async** — `fetch()` or async operations without `AbortController` cleanup on component unmount or route change. Fix: `AbortController` + abort in `useEffect` cleanup + guard `setState` with `signal.aborted` check
- **`[PROD]` React effects without cleanup** — `useEffect` that creates resources without a return cleanup function. Fix: return a function that cleans up ALL resources created in the effect

**Bounded collections:**

- **`[PROD]` Unbounded caches** — in-memory caches (`Map`, plain objects) with no eviction, TTL, or size limit. Fix: `LRUCache({ max, ttl })`, or `WeakMap` when keys are objects
- **`[PROD]` SSE/WebSocket event accumulation** — Server-Sent Events or WebSocket listeners that buffer incoming messages without backpressure or consumption bounds, growing memory linearly with uptime. Fix: sliding window (`splice` when length > max), or process-and-discard pattern

**Reference retention:**

- **`[PROD]` Closures capturing large scope** — callbacks or handlers that close over large data structures unnecessarily, preventing GC of the entire captured scope. Fix: extract only the primitive values needed into local variables before creating the closure
- **`[PROD]` Circular references in persistent structures** — objects referencing each other in long-lived data structures preventing GC

**I/O resources:**

- **`[PROD]` Stream/connection leaks** — database connections, file handles, or readable streams opened without guaranteed `close()`/`destroy()` in error paths. Fix: `try/finally`, TC39 `using`, or connection pooling
- **`[PROD]` Middleware state accumulation** — middleware or interceptors that append to request-scoped arrays/objects that survive the request lifecycle

**Build-time:**

- **`[DEV]` Unconditional build plugin wrapping** — `withSentryConfig()`, `withBundleAnalyzer()`, or similar config wrappers applied regardless of `NODE_ENV`, importing full plugin SDKs in dev mode when the plugin is disabled. Fix: `process.env.NODE_ENV === "production" ? withPlugin(config) : config`
- **`[DEV]` Console logging large objects in hot paths** — `console.log(largeObject)` in per-request middleware, render functions, or event handlers creates serialized string copies retained by the console buffer. Fix: log only identifiers/summaries, or use structured logger with level gating

## HUD Events

Emit bookend events so the HUD tracks this audit:
```bash
source ~/dotfiles/bin/write-hud-state.sh
# At start
write_hud_event "info" "codebase-audit: started"
# At end — report findings count
write_hud_event "info" "codebase-audit: completed — N findings"
```

## Rules

- Do NOT report missing comments, missing types, or missing docs
- Do NOT suggest adding error handling "just in case" for impossible states
- Do NOT recommend abstractions for one-time code
- Every issue must have a concrete file and line reference
- If the codebase is clean, say so. Do not manufacture problems.
