# Closed-loop verification

Reference for designing the feedback an agent uses to check itself, especially
under autonomous or unattended runs where no human sees the intermediate steps.

## The three properties

A verification command is usable by an agent when it is:

**Discoverable** — one predictable place says what to run. `Makefile`,
`package.json` scripts, `AGENTS.md`. Not spread across a README, a CI config, and
memory.

**Decisive** — exit zero means correct, non-zero means broken, with nothing in
between. A command that exits zero while printing errors is read as success,
because agents branch on status before reading output.

**Specific** — the failure text names what broke. A count of failures sends the
agent back to reading source; an assertion carrying expected and actual values
lets it go straight to the cause.

Missing any one of these opens the loop, regardless of how good the tests are.

## Tiering the loop

Agents run verification repeatedly within a single task, so a single slow command
gets skipped. Three tiers work well:

| Tier | Contents | Target |
|---|---|---|
| Fast | Type check, lint, unit tests | Under ~2 min |
| Full | Integration, DB-backed, contract tests | Under ~15 min |
| Release | End-to-end, performance, migration checks | CI only |

Document which tier to run when. The default an agent should reach for is the
fast one, with the full suite before opening a PR. Without this stated, agents
pick from CI config, which is the release tier and far too slow to iterate on.

## Assertion quality

The difference between a usable and unusable failure is almost entirely in the
assertion and the test name.

Weak: a test named `test_upload` asserting that a call returns truthy. The
failure says a test called upload failed. The agent now reads the source to find
out what upload was supposed to do.

Strong: a test named `test_upload_rejects_csv_with_unescaped_parens` asserting a
specific exception type with a message. The failure names the behaviour and the
expected value, and the agent's search space is one function.

The test name is doing real work here — it's the only part of the failure that
carries intent. Names describing the scenario and expected outcome are worth more
to an agent than to a human, because the human can ask someone.

## Determinism

Non-determinism is disproportionately expensive for agents, which have no memory
of last week's flake and will treat a spurious failure as a real one — then
investigate, then sometimes "fix" correct code.

The usual sources, and the usual fixes:

- **Time** — inject a clock rather than reading the system one.
- **Randomness** — seed it, or inject the generator.
- **Ordering** — don't assert on unordered collections without sorting.
- **Shared state** — isolate fixtures per test; a suite that fails only when run
  in a different order is not passing, it's lucky.
- **Network** — stub at the boundary. Tests that hit real services fail for
  reasons unrelated to the change.

Quarantining a known flaky test is better than leaving it in the main path. An
agent trusts a green suite; a suite that's green 80% of the time trains nothing
useful and wastes runs.

## Verification under autonomy

When an agent runs unattended, verification is the only thing standing between a
bad change and a merged one. A few things matter more than they do interactively:

**Verify before reporting success.** The run should end with the command, not
with the edit. An agent that edits and stops has produced an untested change with
a confident summary.

**Make the failure the last thing printed.** Buffered output and a long tail of
passing tests can push the actual failure out of what gets read. Summarise
failures at the end.

**Never let a repair loop run unbounded.** An agent that fixes, re-runs, fails,
and fixes again will happily do that until the budget is gone, drifting further
from the original change each time. Cap attempts and report the last failure
rather than the last edit.

**Keep the verification output.** Under CI this means writing it to a file and
uploading it, not relying on the step log. The run that failed at 3am is
diagnosable only from what was persisted.

## What this doesn't cover

A closed loop confirms the change didn't break something known. It does not
confirm the change was the right one — that's what the plan and the review are
for, and no amount of test coverage substitutes.

The practical implication: expand tests to close the loop on the paths agents
actually touch, not to raise a coverage figure. A test that lets an agent verify
one common class of change is worth twenty that only assert what already worked.
