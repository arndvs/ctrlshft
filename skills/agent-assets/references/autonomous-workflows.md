# Autonomous workflows

Reference for agent workflows that run without a human watching — scheduled
audits, triage jobs, implementation runs triggered by a label. The distinguishing
constraint is that nobody sees the run. Everything about the design follows from
that.

## The failure mode that matters

Interactive agent work fails loudly: you're sitting there, you see it. Autonomous
work fails silently, and the usual way is not a crash — it's a run that completes,
exits zero, and produces nothing. Nobody investigates a green check.

The common causes are all local decisions that look reasonable:

- `|| true` on a step that might legitimately fail
- Catching an exception, logging it, continuing
- A final `exit 0` after a failure branch, to keep the badge green
- Removing an artifact upload to save storage

Each is defensible alone. Together they produce a workflow that has been broken
since March and reports success daily.

**Design rule: a run that did no work must be distinguishable from a run that
failed to do work.** These are different states and they need different exit
behaviour or different recorded status. Collapsing them is what makes the failure
invisible.

## The three trigger shapes

**Scheduled.** Runs on cron whether or not there's anything to do. Suits audits
and periodic checks. The main design problem is repetition — a scheduled job that
re-proposes yesterday's findings gets muted. Needs suppression of known items,
and a distinction between *found nothing* and *everything found is already known*.

**Event-triggered.** Fires on a PR, an issue, a label. Suits review and
implementation. Cheaper to reason about because there's an obvious input and an
obvious place to report back. Watch for loops — a workflow that comments on a PR
and retriggers on comments.

**Label handoff.** One agent proposes, a human applies a label, a second agent
implements. This is worth calling out separately because it puts the human at the
cheapest possible point: acceptance, not review. The proposer files without
consuming attention, nothing is worked without a deliberate decision, and the
implementer only ever touches things somebody already agreed to.

The label handoff also gives you throughput control for free. Volume is bounded
by how much gets tagged, not by how much the proposer finds.

## Contract design

Any workflow calling an agent needs a machine-readable result, not just logs.

Minimum viable shape:

```json
{
  "status": "proposed" | "skipped" | "error",
  "reason": "required for skipped and error",
  "...": "task-specific payload"
}
```

Three rules make this hold up:

**Always write the file**, including on an uncaught exception. Wrap the top level
and emit `status: "error"`. A step that finds no file can only guess; one that
finds a recorded error can report accurately.

**Handle unrecognised status explicitly.** An `if/elif` over known statuses with
no else branch is a silent hole — and an unfamiliar status is more alarming than
a crash, because it means the contract changed underneath you. Print the payload
and fail.

**Distinguish skipped from failed** in the summary. Weeks of legitimate skips look
identical to weeks of silent breakage unless the reason is recorded.

## Observability

The step log is transient, unstructured, and truncated. It is not a record.

- Write agent output to a file, and upload it as an artifact regardless of
  outcome. Retention of a few weeks is enough.
- Capture per attempt when retrying. Two attempts merged into one log make it
  impossible to tell a flake from a consistent failure.
- Merge stderr before the pipe (`cmd 2>&1 | tee log`), so ordering is true.
- Write a run summary — what ran, what it decided, what it filed. This is what
  makes a Monday-morning glance sufficient.

Under CI, stdout is a pipe and therefore block-buffered, and an abrupt exit can
discard queued writes — usually the last line, which is usually the important
one. See `logging-audit` for the detail; the practical rule is to set an exit
code and return rather than exiting mid-flush.

## Bounding autonomy

Unattended runs need limits that interactive work doesn't:

**Cap retries.** Two attempts is usually right. Unbounded repair loops drift
further from the original intent with each pass and consume the budget.

**Cap output volume.** A run that files fifteen issues gets its label muted, and
the good findings go unread with the rest. Bound findings per run explicitly.

**Use concurrency groups.** Two runs of the same workflow filing duplicate issues
is a distinctive and annoying failure.

**Scope the token.** Least privilege matters more here, since nobody reviews the
diff before it's pushed.

**Prefer proposing to acting** wherever the change isn't mechanically reversible.
Renames and moves are test-covered and safe to automate; anything touching module
boundaries or data shape wants a human at the acceptance point.

## When not to build one

If the task runs less than weekly, or its output needs a human decision anyway,
a committed command someone invokes is cheaper and fails visibly. Autonomy is
worth its complexity when the work is repetitive, the verification is automated,
and the cost of a missed run is low.

The version worth avoiding is a workflow built because it was interesting, that
nobody reads the output of. It costs money on a schedule and produces the
appearance of rigour.
