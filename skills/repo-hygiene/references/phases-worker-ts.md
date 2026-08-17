# Phases — Worker TypeScript

For Cloudflare Worker repos written in TypeScript (e.g. `MCRDSE-Content-Ship`). The goal is structure, typing, and DRY across handlers, services, and scripts. Walk in order; current phase is the first whose exit criteria are unmet.

---

## Phase 0 — Safety net

**Exit criteria**
- `npm run typecheck` and the test suite pass on a clean checkout
- CI runs typecheck + tests on every PR
- `.refactor/state.json` exists and validates

**Task pool**
- Get typecheck and tests green (fix errors only — no refactoring)
- Add the CI workflow
- Add a route/handler inventory at `.refactor/routes.json`

---

## Phase 1 — Structure

**Exit criteria**
- A consistent `src/` layout exists (handlers, services, lib, types)
- No logic lives at repo root or in a catch-all `scripts/` that duplicates `src/`
- Entry point is thin — it wires handlers, it doesn't implement them

**Task pool**
- Establish the `src/` directory convention and move root-level code into it
- Split the entry point: route dispatch from handler implementation
- Separate pure logic (services) from I/O (bindings, fetch, D1)

---

## Phase 2 — DRY extraction

**Exit criteria**
- No file exceeds 300 lines
- Zero duplicated blocks of ≥ 15 lines in ≥ 2 files
- Shared helpers (auth, validation, error handling, response shaping) are extracted
- Typecheck passes with no `any` in new code

**Task pool**
- Extract a repeated block (response wrapper, auth check, validation) into a shared helper, replacing every occurrence
- Split an oversized file into modules — top-down, largest first
- Parameterize near-duplicates into one function with options

---

## Phase 3 — Typing & contracts

**Exit criteria**
- All handlers and services have explicit types
- Shared request/response types exist for the API surface
- No `any` or `@ts-ignore` without a documented reason

**Task pool**
- Add explicit types to untyped handlers/services
- Define shared request/response types and wire them through
- Replace `any` with proper types, one module at a time

---

## Phase 4 — Data & config

Applies if the worker has D1/KV/R2 bindings or hardcoded config.

**Exit criteria**
- Database access is centralized (no scattered raw queries)
- Config/secrets are not hardcoded in source
- Migrations are versioned and documented

**Task pool**
- Centralize DB access into a data layer
- Move hardcoded config into bindings/env
- Document the migration workflow

---

## Phase 5 — Ratchet

**Exit criteria**
- Lint rules enforce the constraints (max file length, no `any`)
- Rules run in CI and fail the build
- README documents the structure and typing conventions

**Task pool**
- Add file-length and no-`any` lint rules
- Write the conventions doc
- Propose disabling the nightly cron

Once these are met the loop is finished. Say so and stop.
