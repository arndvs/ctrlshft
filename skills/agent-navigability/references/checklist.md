# Structural checklist

Reference for Step 2. Check these against the repo's own dominant pattern, not
against this list as an ideal — a repo that consistently does something unusual
is navigable, and a repo that inconsistently does the right thing is not.

## Entry points

- One obvious start per service, at a predictable path.
- Startup and configuration wiring visible from that file, not scattered.
- If several executables exist, a naming scheme that distinguishes them.
- Dead or superseded entry points removed, or marked as dead in a way that a
  reader hits before editing.

## Naming

The test for any name: **does grepping it return roughly the places that
matter?**

- Domain nouns over generic ones. `InvoiceLineItem` over `Item`.
- Function names describing what happens, not that something happens.
  `sanitizeTableName` over `processInput`.
- File names matching their primary export.
- Consistent casing and pluralisation within a directory — inconsistency here
  makes searches miss.
- Watch for repo-wide overloaded terms. If `config` means four different things,
  no search for it is useful.

Rank findings by centrality. A generic name on a core type is expensive; on a
loop variable it's free.

## Types and data flow

- Named types at module boundaries; anonymous dicts and `any` only inside a
  single function.
- Errors as named types rather than strings, so handlers are findable.
- Enums or constants for closed sets instead of bare string literals.
- Types defined near where they're owned, not accumulated in one dumping ground —
  a single 2,000-line types file is a search bottleneck, not a convenience.

The property being audited is followability: can an agent grep a type and get the
full producer-to-consumer path?

## Files and modules

- Rough 1,000-line ceiling, applied with judgment. Exempt generated code,
  migrations, lock files, and fixtures.
- One primary responsibility per file. The signal is a file whose name describes
  only part of what's in it.
- No `utils`/`helpers`/`misc` catch-alls. These attract unrelated code and are
  the first place an agent looks and the last place it should.
- Directory depth under about four levels for hand-written source.

## Tests

- Test paths derivable from source paths by a fixed rule.
- Test file naming consistent enough to glob.
- Fixtures and factories in a predictable location.
- If the repo has multiple test types (unit, integration, e2e), the split should
  be visible from the path.

The property: given a source file, can an agent construct the test path without
searching, and know where a new test goes?

## Commands

- Run, test, lint, build, and format in one predictable place — `Makefile`,
  `package.json` scripts, `justfile`, or documented in `AGENTS.md`.
- Commands work from the repo root, or the required directory is stated.
- Local commands not exclusively documented inside CI config. CI is the last
  resort an agent falls back to, and it's usually wrong for local use.

## Agent-facing documentation

- Root `CLAUDE.md` or `AGENTS.md` with layout, commands, and conventions.
- Subsystem-level files where constraints are non-obvious — not everywhere.
- Vendored third-party docs (`ai_docs/` or similar) for libraries agents
  repeatedly look up, pinned to the version in use.
- Documentation stating what *not* to touch: generated files, vendored code,
  deprecated paths. This prevents a specific expensive failure — an agent
  carefully editing a file that gets overwritten on the next build.

## Consistency signals

Worth a specific pass, since these are what break search strategies:

- Same organising principle across features (all by layer, or all by domain).
- Same import style and path aliasing throughout.
- Same error-handling shape at equivalent boundaries.
- Same configuration mechanism across services.

Where two patterns coexist, check whether one is a partial migration. If so, the
finding is the unfinished migration, not the inconsistency — and the fix is
finishing or reverting it, not adding a third pattern.
