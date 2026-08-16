# Phases — Generic

Fallback phase model for repos that don't match Astro, static-HTML, worker-TS, or Python. Use the generic audit signals (largest files, duplicated blocks, oversized count). Walk in order; current phase is the first whose exit criteria are unmet.

---

## Phase 0 — Safety net

**Exit criteria**
- The build/typecheck/test command passes on a clean checkout
- CI runs it on every PR
- `.refactor/state.json` exists and validates

**Task pool**
- Get the build green (fix errors only — no refactoring)
- Add the CI workflow
- Add a file inventory

---

## Phase 1 — Structure

**Exit criteria**
- A consistent source layout exists (no logic at repo root)
- Entry points are thin — they wire, they don't implement

**Task pool**
- Establish the source directory convention and move root-level code into it
- Split the entry point from implementation

---

## Phase 2 — DRY extraction

**Exit criteria**
- No file exceeds 300 lines
- Zero duplicated blocks of ≥ 15 lines in ≥ 2 files
- Shared helpers are extracted

**Task pool**
- Extract a repeated block into a shared module, replacing every occurrence
- Split an oversized file into modules — top-down, largest first
- Parameterize near-duplicates into one function with options

---

## Phase 3 — Typing & config

**Exit criteria**
- Code is typed (or type-hinted)
- Config/secrets are not hardcoded in source

**Task pool**
- Add types/type hints to untyped code
- Move hardcoded config into env/config files

---

## Phase 4 — Data

Applies if the repo has embedded data that should be structured.

**Exit criteria**
- Data is in structured files, not embedded in code

**Task pool**
- Move embedded data into structured data files

---

## Phase 5 — Ratchet

**Exit criteria**
- Lint rules enforce the constraints
- Rules run in CI and fail the build
- README documents the conventions

**Task pool**
- Add lint rules
- Write the conventions doc
- Propose disabling the nightly cron

Once these are met the loop is finished. Say so and stop.
