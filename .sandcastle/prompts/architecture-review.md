# TASK

You are running the scheduled architecture-review pass. Find one fresh deepening opportunity in this codebase and draft it as a PRD.

This is an unattended CI run. There is no user to interview and no HTML report to write. Your job is:

1. List prior proposals labelled `source:architecture-review` (open and closed) so you do not re-propose them.
2. Read `{{CONTEXT_DOC}}` and relevant ADRs under `{{ADR_DIR}}`.
3. Explore the codebase.
4. Pick **one** top candidate.
5. Draft a PRD issue title and body.
6. Keep your final recommendation, candidate notes, and skip rationale in the session. A follow-up extraction pass will ask you to report the outcome.

The workflow will create the GitHub issue and apply the `source:architecture-review` label. Do not create the issue yourself.

# REVIEW METHOD

Look for architectural deepening opportunities rather than cosmetic cleanup:

- Modules where deletion would be hard because responsibilities are tangled.
- Concepts that appear in several places without a single named abstraction.
- Workflows where state transitions are implicit or duplicated.
- Boundaries where tests, docs, or types do not protect the intended design.
- Existing patterns that could be made smaller by removing indirection.

Also scan for these operational health dimensions:

- **Resource management** — code that will leak memory, connections, or handles at runtime. Scan for each of these (tagged `[PROD]` for production hazards, `[DEV]` for dev-mode hazards):
  - `[PROD]` Unbounded module-scope collections (Map, Set, Array) with no eviction, TTL, or max size. Fix: LRU/TTL eviction + `globalThis` for HMR safety
  - `[PROD]` Event listeners / timers / observers without cleanup. Fix: `AbortController.signal` or manual removal in cleanup path
  - `[PROD]` `fetch()` without `AbortController` in components. Fix: abort in `useEffect` cleanup
  - `[PROD]` Streams, DB connections, or file handles without guaranteed `close()` in error paths. Fix: `try/finally` or TC39 `using`
  - `[BOTH]` Per-request SDK client instantiation instead of singletons. Fix: `globalThis.__client ??= new SDK(key)`
  - `[DEV]` Module-scope state duplicated on every HMR cycle without `globalThis.__x ??=` protection
  - `[DEV]` Large inline data arrays (100+ entries) at module scope re-allocated on HMR. Fix: extract to JSON + lazy accessor with `globalThis`, NOT deletion
  - `[DEV]` Build plugin wrappers loaded unconditionally regardless of `NODE_ENV`. Fix: conditional ternary on `process.env.NODE_ENV`
  - `[PROD]` SSE/WebSocket listeners accumulating events without backpressure. Fix: sliding window or process-and-discard
  - `[DEV]` Console logging large objects in hot paths (middleware, render, event handlers). Fix: log identifiers/summaries only, or structured logger with level gating
- **Security posture** — secrets, credentials, API keys, or tokens that are hardcoded, committed in plaintext, or insufficiently protected. `.env` files checked into version control. Sensitive values logged or exposed in error messages.
- **Dead code at module boundaries** — exported symbols with zero consumers across the repo, files with no inbound imports, unused dependencies in `package.json`, unreachable code behind feature flags that shipped.
- **ADR drift** — code that has diverged from decisions recorded in `{{ADR_DIR}}`. An ADR says "use X" but the codebase now does Y in some modules. Flag the drift, not the ADR.
- **Test coverage gaps** — public API surfaces, module boundaries, and critical paths with no test protection. Functions that handle error/edge cases but are never tested with those inputs. Integration seams (API routes, middleware, hooks) where a regression would be caught only in production.

Prefer one proposal that would make future changes easier to reason about. Do not propose work already covered by a prior `source:architecture-review` issue, even if the wording differs.

# CONTEXT RULES

- Treat ADRs as binding. Do not propose changes that contradict a recorded decision.
- Respect project coding standards from `{{CODING_STANDARDS}}` if the file exists.
- Read-only on the repo. No commits. No edits to `{{CONTEXT_DOC}}`, ADRs, or source files.
- One PRD per run. If every reasonable candidate is already covered, record why no fresh proposal should be made and stop.
- No questions to a user. Make the call.
