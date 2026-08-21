---
name: agent-testability
description: Audit whether a codebase gives a coding agent a reliable way to verify its own work, and propose fixes. Use whenever an agent reports success but the change is broken, when tests exist but don't catch regressions, when the feedback loop is too slow or too noisy for an agent to use, when test failures don't say what broke, or when someone asks how to make a repo safe for autonomous or unattended agent runs. Also use for requests like "why does it keep saying it's done when it isn't", "review our test setup for agents", "what should agents run before opening a PR", or planning a testing strategy where the consumer is an agent rather than a human.
---

# Agent testability audit

An agent that cannot check its own work will report success anyway. Not from
dishonesty — it finished the edit, nothing contradicted it, so it says done. Every
unverified change is a coin flip that gets discovered later by a human, which is
exactly the cost autonomy was supposed to remove.

The question throughout: **can an agent tell, without a human, whether the change
it just made is correct?** That is narrower than "is this well tested." A repo
with excellent coverage can still fail this if the suite takes forty minutes, or
if failures print nothing useful, or if nobody can tell which command to run. And
a modest suite can pass it if it's fast, obvious, and specific.

Related skills: `logging-audit` covers whether runtime output is legible;
`agent-navigability` covers whether the code is. This one covers whether the
loop closes.

---

## Step 1: Close the loop yourself

Don't read the test directory and form opinions. **Make a small change and try to
verify it the way an agent would.** Add a field, change a function's behaviour,
or deliberately break something small — then find out whether the repo tells you.

Record, concretely:

- What command you ran, and how you worked out it was the right one
- How long it took before you had a verdict
- Whether the failure named the thing that broke, or just reported that something did
- Whether a passing run actually meant anything, or the change wasn't covered

Then the harder test: **break something on purpose and see if the suite notices.**
A suite that stays green when you delete a branch is not a feedback loop, it's
decoration. This single check finds more than any amount of reading.

That log is the finding set.

## Step 2: Establish what exists

Find the de facto setup before recommending anything:

- Framework and runner, and whether more than one is in use
- Where tests live relative to source, and whether the rule is consistent
- What CI runs, and whether it matches what a developer would run locally
- Roughly how long the fast path takes
- Whether there's a documented pre-commit or pre-PR command

Audit against what's there. A repo with an unusual but consistent setup is
workable; the finding in that case is that it's undocumented, not that it's
wrong. Never halt because there's no written testing standard — note its absence
as a finding and continue.

---

## Step 3: What to look for

### Blocking

**No command an agent can run to check its work.** If verification requires
starting services by hand, clicking through a UI, or knowing which of four
scripts is current, the loop is open. Everything else here is secondary to this.

**A suite that passes when the code is broken.** Established in Step 1. Common
causes: tests asserting that a function returns without asserting what, mocks
that stub the logic under test, snapshot tests regenerated on failure. Report
the specific test, not the coverage number.

**Failures that don't identify what broke.** An agent branches on the failure
text. A bare assertion mismatch, a stack trace with no message, or a suite that
reports only a count sends it back to reading source. Assertions carrying the
expected and actual value, and test names describing the behaviour, are what make
a failure actionable.

**Tests that fail intermittently.** Flakiness is worse for an agent than for a
human, because the agent has no memory of the test being flaky last week. It
treats the failure as real, investigates, and often "fixes" working code. A known
flaky test is a defect with a higher priority than most feature bugs.

**Verification that exits zero on failure.** A script that prints errors and
returns success is read as success. Agents check exit status before reading
output. Applies to wrapper scripts, `npm test` chains that swallow codes, and
anything piped without `pipefail`.

### Worth fixing

**A fast path that isn't fast.** If the only way to check anything takes twenty
minutes, an agent either skips it or burns the run waiting. There should be a
subset — unit tests, type check, lint — that returns in a minute or two and is
documented as the thing to run first.

**Tests that don't mirror source structure.** When the test path is derivable
from the source path, an agent extends the right file. When it isn't, it either
searches or writes a duplicate somewhere else.

**Untestable seams.** Logic reachable only through a running server, network
calls with no injection point, time and randomness read directly from globals.
Each one pushes verification out of reach and into manual checking.

**No fixtures or factories.** If constructing a valid object takes thirty lines
of setup, the agent writes fewer tests and worse ones. A factory is leverage.

**Coverage concentrated away from risk.** Thorough tests on pure helpers and
nothing on the path that writes to storage. Report by location and consequence,
not as a percentage — a coverage number is not a finding.

**No documented verification sequence.** Which command before committing, which
before opening a PR. If it's implicit, every session guesses, and the guess is
usually the CI config, which is slow and often wrong for local use.

### Optional

**Redundant assertions across layers.** The same invariant checked at unit,
integration, and end-to-end level. Slows the loop without adding signal. Only
raise alongside a speed finding.

---

## Step 4: Report

Lead with what stays unverified.

```
### Blocking

**`app/server/ingest.py`** — no test exercises the CSV-to-SQLite path. Deleting
the error branch entirely leaves the suite green, so an agent editing this file
gets a passing run that means nothing.

Add a test that ingests a malformed fixture and asserts on the raised error type.

### Worth fixing

**`pytest`** takes 14 minutes because integration tests share the default marker.
Nothing an agent can run for a quick verdict.

Mark integration tests and document `pytest -m "not integration"` as the fast
path in `AGENTS.md`.
```

Every finding needs a location, what goes unverified, and a fix. "Coverage is
low" is not a finding. "An agent can delete this branch and the suite stays
green" is.

**Sequence by loop-closing value, not by coverage gain.** One test on the
critical path is worth more than twenty on helpers, because it converts a whole
class of change from unverifiable to verifiable.

If the loop already closes, say so. Recommending more tests on a repo that
already catches its own regressions costs runtime and review attention for
nothing.

---

## A note on what tests can't do

A closed loop tells an agent whether it broke something known. It says nothing
about whether it built the right thing, and nothing about failure modes nobody
wrote a test for.

So test findings pair with logging findings rather than replacing them. Tests
catch known regressions; runtime output is what makes the unknown ones
diagnosable. A repo with a green suite and silent error paths still produces
agent runs that fail in ways nobody can reconstruct.
