# Commands and vendored documentation

Reference for the smaller, cheaper assets: reusable prompts and local copies of
external reference material.

## Reusable commands

A command is a committed prompt an agent can invoke by name. The value isn't
saved typing — it's that a committed prompt is identical on every run, visible in
review, and improvable in one place. Retyped prose drifts, and the drift only
surfaces when a run fails oddly.

### What earns a command

Three occurrences. A sequence performed three times has proven it recurs, and
that's the threshold worth acting on — earlier is speculative, later means the
drift has already happened.

Typical candidates:

- **Priming.** Orient a fresh session: list tracked files, read the key files,
  summarise the layout. Worth having because it makes orientation a fixed cheap
  step instead of an improvised variable one.
- **Setup and start.** Install, configure, run. Usually already written as prose
  in a README, which means the work is transcription.
- **Verification.** The specific sequence before committing or opening a PR.
- **Recurring review shapes.** Whatever the team asks for repeatedly in the same
  words.

### How to write one

Start with the literal text that worked. Not a cleaned-up version — the actual
prompt, including the parts that felt redundant, because you don't yet know which
parts were load-bearing.

Generalise on the second use case. Commands parameterised in advance are usually
parameterised on the wrong axis, and an over-general command is harder to use
than two specific ones.

Keep priming separate from task instructions. Priming answers *where am I*; the
task prompt answers *what am I doing*. Bundled, you re-pay orientation on every
variant of the task.

Commands can invoke other commands. That composes well — a `start` command that
calls `prime` first stays correct when priming changes.

### Anti-patterns

- **Commands wrapping a confusing process.** Makes it repeatable, not simple. Fine
  as an interim step; say so rather than treating the finding as closed.
- **Near-duplicates.** Three variants differing by one word should be one command
  with an argument.
- **Stale commands.** Referencing deleted scripts or renamed paths. They fail
  confusingly rather than cleanly, since the agent tries to work around them.
- **Commands nobody runs.** Retire them. They're read and considered whenever the
  directory is listed.

## Vendored documentation

Local copies of external docs — `ai_docs/`, `docs/vendor/` — that agents would
otherwise fetch.

Three real benefits: no network round trip, no fetch failure mid-run, and the
docs match the version actually in use rather than whatever is current upstream.
The third matters most and is the least obvious. A library that changed its API
between versions will otherwise produce confidently wrong code, and the agent has
no way to detect the mismatch.

### What's worth vendoring

- Libraries central to the codebase, especially with a recent breaking change
- Internal API docs behind authentication
- Anything agents demonstrably fetch repeatedly

Not worth it: stable material the model already knows well, anything peripheral,
anything you won't refresh.

### The staleness trap

Vendored docs look authoritative and rot invisibly. Nothing fails when they go
out of date — the agent just follows them.

Minimum hygiene: record the source URL, the version, and the fetch date at the
top of each file. Then a stale copy is at least detectable. If a doc's version no
longer matches what's in the lockfile, that's a finding.

If nobody will refresh them, deleting is better than keeping. A fetch at runtime
is slower and less reliable but can't be silently wrong about the version.

## Orientation files

`CLAUDE.md`, `AGENTS.md`, and subsystem equivalents. Covered in
`agent-navigability`; the asset-side concerns are:

**Length.** Loaded every session, so every line competes with the task. Past a
page, ask what can go.

**Accuracy over completeness.** A short accurate file beats a thorough stale one
by a wide margin. Wrong orientation produces confident wrong work.

**Aspiration.** Files describing intended rather than actual conventions produce
changes inconsistent with their surroundings. Either fix the code or fix the
file.

**Scope.** Subsystem files load only when that area is in play, so they can carry
specifics the root file can't afford. Add them where local constraints differ,
not uniformly.
