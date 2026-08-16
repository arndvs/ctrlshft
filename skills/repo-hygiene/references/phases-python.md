# Phases — Python

For repos that are Python scripts/runbooks with no framework (e.g. `mcrdse-outreach`). The goal is a package structure, shared modules, and DRY across scripts. Walk in order; current phase is the first whose exit criteria are unmet.

---

## Phase 0 — Safety net

**Exit criteria**
- A test runner is configured and passes on a clean checkout
- CI runs the tests on every PR
- `.refactor/state.json` exists and validates

**Task pool**
- Get the tests green (fix errors only — no refactoring)
- Add the CI workflow (pytest or the repo's runner)
- Add a module/script inventory

---

## Phase 1 — Package structure

**Exit criteria**
- Code lives in a proper package (e.g. `src/` or a named package dir), not loose root scripts
- Entry points (CLI scripts) are thin wrappers over package modules
- No duplicated imports of the same logic across scripts

**Task pool**
- Establish the package layout and move root scripts into it
- Convert root scripts into thin CLI entry points that import from the package
- Add `pyproject.toml`/`requirements.txt` if missing

---

## Phase 2 — DRY extraction

**Exit criteria**
- No file exceeds 300 lines
- Zero duplicated blocks of ≥ 15 lines in ≥ 2 files
- Shared helpers (auth, HTTP, config, logging) are extracted into modules

**Task pool**
- Extract a repeated block (HTTP client, auth, config loading) into a shared module, replacing every occurrence
- Split an oversized script into modules — top-down, largest first
- Parameterize near-duplicates into one function with options

---

## Phase 3 — Typing & config

**Exit criteria**
- Functions have type hints
- Config/secrets are not hardcoded in source (env vars / config files)
- No `except: pass` swallowing errors silently

**Task pool**
- Add type hints to untyped functions
- Move hardcoded config/secrets into env vars or a config module
- Replace silent exception swallowing with explicit handling

---

## Phase 4 — Data & runbooks

Applies if the repo has data files or markdown runbooks that duplicate code.

**Exit criteria**
- Data is in structured files (JSON/CSV), not embedded in scripts
- Runbooks reference the actual commands/scripts rather than duplicating them

**Task pool**
- Move embedded data into structured data files
- Reconcile runbooks with the actual scripts they describe

---

## Phase 5 — Ratchet

**Exit criteria**
- Lint rules enforce the constraints (max file length, no bare `except`)
- Rules run in CI and fail the build
- README documents the package structure and conventions

**Task pool**
- Add file-length and bare-`except` lint rules
- Write the conventions doc
- Propose disabling the nightly cron

Once these are met the loop is finished. Say so and stop.
