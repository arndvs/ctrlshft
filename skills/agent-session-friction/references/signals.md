# Friction signal catalogue

Each signal names what to look for in a transcript, which lens it belongs to, and
the attribution test that separates a repo problem from an agent problem.

Signals are grouped by lens so observations flow into the same taxonomy the
weekly audit publishes from.

---

## Navigability signals

### `wasted-reads`
**Lens:** `structure` · **Look for:** files opened, then never edited, never
referenced in later reasoning, never cited in the final response.

The cleanest friction signal available. Count only reads with no downstream use —
reading a file to rule it out *is* useful when something pointed there.

**Attribution:** repo's fault when nothing distinguished the discarded files from
the right one. Agent's fault when the correct file was named obviously and got
skipped anyway.

### `search-churn`
**Lens:** `naming` · **Look for:** three or more distinct search terms aimed at
the same target, or searches returning result counts too large to use followed by
a fallback to reading files.

This is the direct measurement of the naming test — does grepping a name return
roughly the places that matter. Here you see it fail.

**Attribution:** repo's fault when each term was a reasonable guess. Agent's fault
when the terms were near-duplicates of each other.

### `location-uncertainty`
**Lens:** `structure` · **Look for:** the agent asking which file to edit,
stating uncertainty about where something lives, or editing one file and then
switching to another for the same purpose.

The switch pattern is the strongest form: it means two files plausibly owned the
same behaviour. Record the fingerprint against the ambiguous pair.

### `orientation-cost`
**Lens:** `orientation` · **Look for:** the number of tool calls before the first
productive action — an edit, or an answer that used what was read.

Establish a rough baseline across sessions; flag episodes well above it. High
orientation cost with no `AGENTS.md` present is an orientation finding. High
orientation cost *with* one present is a stronger finding: the asset exists and
isn't doing its job.

### `truncated-read`
**Lens:** `structure` · **Look for:** file reads that hit a limit, or the agent
paging through one file in chunks.

Direct evidence of the oversized-file problem, with the specific file named.

### `type-trace-cost`
**Lens:** `types` · **Look for:** the agent reconstructing a data shape by
reading successive call sites, or reasoning about what keys a dict contains.

Evidence that data crossing a boundary was untyped. A named type would have made
this one search.

### `user-corrects-location`
**Lens:** `structure` · **Look for:** the user telling the agent where something
is, which file to edit, or that it changed the wrong thing.

Cheap to detect and unusually reliable — a human paid attention to route the
agent, which is exactly the cost the repo should have absorbed. Weight these
higher than agent-side signals.

---

## Testability signals

### `no-verification`
**Lens:** `verification` · **Look for:** an episode ending with mutations and no
test, build, lint, or type check run.

**Not-applicable** when the repo has no verification path at all — that's a
different finding, recorded once, not per episode.

### `verification-not-found`
**Lens:** `verification` · **Look for:** the agent searching for how to run
tests, reading CI config to find a local command, or trying several invocations
before one worked.

Discoverability failure. The fix is documenting the command, not adding tests.

### `uninformative-failure`
**Lens:** `verification` · **Look for:** a failure followed by the agent reading
source to work out what the failure meant.

The failure text didn't name what broke. Record the specific test.

### `repair-loop`
**Lens:** `verification` · **Look for:** three or more edit-then-rerun cycles on
the same target.

Ambiguous between a hard problem and a bad feedback loop. Only record when the
reruns produced no new information — the same opaque failure each time.

### `flake-suspected`
**Lens:** `verification` · **Look for:** a check failing then passing with no
relevant change between.

High value, because a human would have shrugged and re-run. Record even on a
single occurrence; consolidation will decide.

### `verification-passed-then-broken`
**Lens:** `verification` · **Look for:** a later session, or the user, reporting
that something a previous session verified was broken.

The strongest signal available and the hardest to detect, since it spans
sessions. Worth the effort: it means the suite passes while the code is broken,
which is the blocking finding in `agent-testability`.

---

## Logging signals

### `instrumentation-added-to-diagnose`
**Lens:** `logging` · **Look for:** the agent adding print or log statements to
understand behaviour, then removing them.

Elegant signal. The agent had to instrument the code because the code wouldn't
tell it what was happening — precisely the gap `logging-audit` looks for, caught
in the act.

### `silent-failure-investigated`
**Lens:** `logging` · **Look for:** an error surfacing with no message, no stack
trace, or a generic wrapper, and the agent reading source to locate the origin.

Record the fingerprint at the swallowing boundary, not where the symptom
appeared.

### `output-volume-cost`
**Lens:** `logging` · **Look for:** a single command's output consuming a large
share of context, or compaction triggered immediately after a command.

Evidence that the hot-path volume finding is real and expensive.

---

## Assets signals

### `sequence-rederived`
**Lens:** `assets` · **Look for:** the agent reconstructing a multi-step
procedure that exists in a README, CI config, or a previous session.

Feeds the three-occurrences-makes-a-command rule with actual occurrence counts
rather than someone's impression.

### `external-doc-fetched`
**Lens:** `assets` · **Look for:** web fetches for library documentation.

Repeated fetches of the same source across sessions are the vendoring case, with
evidence.

### `stale-asset-followed`
**Lens:** `assets` · **Look for:** the agent following guidance from an
orientation file and hitting something that no longer matches — a missing
directory, a renamed script.

Blocking severity. Confident wrong work, and it will recur every session until
the file is fixed.

### `capability-missing`
**Lens:** `assets` · **Look for:** the agent unable to complete work for lack of
a tool, credential, or permission.

---

## Signals to deliberately ignore

**Long duration.** A hard task takes a while. Not friction without a specific
wasted action.

**High token count.** Same. Large context can be efficient.

**Many turns with an engaged user.** Collaborative iteration is not friction.
Friction is the user *correcting* the agent, not directing it.

**The agent asking a clarifying question.** Usually good behaviour, and reading
it as friction pressures agents toward guessing.

**Failed edits from malformed tool calls.** Agent-side mechanical error, nothing
to do with the repo.
