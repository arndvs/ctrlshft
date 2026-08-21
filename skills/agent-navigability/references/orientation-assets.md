# Orientation assets

Cheaper than restructuring, and often most of the benefit. Reach for these when a
structural fix is expensive, when the repo can't be reorganised right now, or as
a first step before a larger refactor.

## `AGENTS.md` / `CLAUDE.md`

Written for something with no memory of this repo. Keep it short — it's loaded on
every session, so every line competes with the actual task for context.

What earns a place:

- **Layout in three or four lines.** Where services live, where tests live, what
  the top-level directories are for.
- **Commands.** Run, test, lint, build. Exact invocations, with the directory
  they run from.
- **Conventions that aren't inferable.** Naming rules, error-handling shape,
  which logger to use. Skip anything obvious from reading two files.
- **Do-not-touch list.** Generated files, vendored code, deprecated paths. This
  prevents an expensive and common failure: careful edits to a file that's
  overwritten on the next build.
- **Known traps.** The test that's flaky, the service that must start first, the
  migration that can't run twice.

What doesn't: restating the README, architectural philosophy, aspirational
conventions the code doesn't follow. An `AGENTS.md` describing a codebase that
doesn't exist is worse than none — it produces confident wrong edits.

**Subsystem files** work well where local constraints differ from the root. They
load only when that area is in play, so they can be more specific than the root
file affords. Add them where an agent would otherwise need tribal knowledge, not
uniformly.

## Priming commands

A reusable command that orients a fresh session — typically listing tracked
files, reading a few key files, and summarising the layout.

The value is that exploration becomes a fixed, cheap, repeatable step rather than
an improvised one that varies per session. It also makes the orientation cost
visible: if priming pulls in 30k tokens, that's a measurement of how unnavigable
the repo is, and a reason to fix the structure rather than paper over it.

Keep priming and task instructions separate. Priming answers *where am I*; the
task prompt answers *what am I doing*. Bundling them means re-paying orientation
on every variant of the task.

## Vendored documentation

A directory — `ai_docs/`, `docs/vendor/` — holding local copies of third-party
documentation agents repeatedly fetch.

Three benefits: no network round trip, no fetch failures mid-run, and the docs
match the version actually in use rather than whatever is current upstream. That
last one matters more than it sounds; a library that changed its API between
versions will otherwise produce confidently wrong code.

Worth vendoring: libraries central to the codebase, anything with a recent
breaking change, internal API docs that live behind auth. Not worth it: stable
standard-library material the model already knows, or anything that would go
stale without a refresh process. Note the version and the date fetched — stale
vendored docs are a trap, since they look authoritative.

## Reusable commands

When the same multi-step instruction is issued three times, it should be a
committed command file rather than retyped prose.

The reliability argument matters more than the convenience one: a committed
command is identical every time, reviewable in a PR, and improvable in one place.
Retyped prose drifts, and the drift is invisible until a run fails oddly.

Start with the literal text that worked. Generalise only once a second use case
proves what actually varies — commands parameterised in advance are usually
parameterised on the wrong axis.

## When to prefer these over restructuring

Orientation assets are strictly cheaper: no merge conflicts, no broken mental
maps, no review burden, reversible in one commit. Prefer them when the structural
fix is large, when the code is under active development by others, or when you
aren't yet confident the structural diagnosis is right.

They stop being sufficient when the problem is ambiguity rather than ignorance.
A document can say where things live; it can't make two files that plausibly own
the same behaviour distinguishable, and it can't make an overloaded name
searchable. Those need the structural fix.

The failure mode to avoid is an `AGENTS.md` that grows into a manual explaining
around structural problems. Length is the signal — when the orientation file
needs a section explaining which of several similar directories is real, fix the
directories.
