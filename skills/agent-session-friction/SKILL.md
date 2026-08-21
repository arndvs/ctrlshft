---
name: agent-session-friction
description: Analyse a completed agent session transcript for evidence that the codebase made the work harder than it needed to be, and record those observations for later consolidation. Use at the end of an agent run, when reviewing a transcript to find what slowed an agent down, when deciding which repo problems are actually costing something, or when someone asks why a run took so many turns or burned so much context. Also use for requests like "audit this session", "what friction did this run hit", "post-run review", or when building automation that collects friction evidence across many runs. Produces observations with measured cost, not issues — publishing is a separate consolidation step.
---

# Session friction audit

The other audit skills manufacture their evidence: attempt a task, note where you
struggled. A finished session transcript already contains that, with better
evidence than any static scan produces — actual searches that returned nothing
useful, actual files opened and discarded, actual failures that named nothing.

This skill reads that record and converts it into observations with measured
cost. It does not file issues. A single session is `n=1`, and filing on `n=1`
produces findings driven by one unlucky run. Observations accumulate; a separate
consolidation step ranks by how often each thing actually cost something and
publishes the top few.

That division is the whole point. Static analysis infers that a name is hard to
search. This measures that it *was*.

---

## Two modes

This skill runs at two different moments, and the split matters.

**Collect** — at session end, via a hook, unconditionally. Mechanical only: parse
the transcript, segment episodes, count signals, write records. No judgement, no
model call. `scripts/collect-friction.py` does this; the skill is only needed
when adapting it to a new harness or adding a signal.

A hook rather than a final task in the prompt, because a task at the end of a
prompt gets dropped when a session ends messily — and messy endings are exactly
the high-friction sessions most worth recording. That is selection bias against
the data the whole system depends on.

**Attribute** — weekly, during consolidation, by an agent. This is where the
judgement happens: was each ranked candidate the repo's fault or the agent's,
and what is the actual finding? Everything below applies here.

Attribution is deliberately *not* done at session end. Judging repo-fault versus
agent-fault from a single session is the same `n=1` problem as filing from one
session — one instance can't show a name is unsearchable, but nine across six
sessions makes it obvious. Attribution gets better with aggregate context, so it
belongs where the aggregate is.

---

## The framing that matters most

**You are auditing the repository, not the agent.**

Every signal here is ambiguous between "the codebase made this hard" and "the
agent worked badly." Get that attribution wrong and the output is a performance
review of a language model, which fixes nothing.

The dividing question: **would a competent engineer new to this repo have hit the
same wall?** If yes, it's a finding. If the agent re-read a file it had already
read, forgot its own earlier conclusion, or thrashed on something clearly stated
in the README, that's the agent, and it goes in the discard pile.

Rules of thumb:

| Signal | Repo's fault | Agent's fault |
|---|---|---|
| Read files that turned out irrelevant | Nothing distinguished them from the right one | The right one was named obviously |
| Repeated searches | Each term was reasonable and returned noise | Terms were near-duplicates |
| Re-read the same file | File too large to hold, or split across places | Simple context mismanagement |
| Long orientation | No entry point, no `AGENTS.md` | Orientation asset existed and was skipped |

When genuinely unsure, discard. A false finding costs more than a missed one —
it burns review attention and teaches people the audit is noisy.

---

## Step 1: Capability detection

Before concluding anything is absent, establish what the transcript can show.
A transcript that doesn't record tool calls cannot support "the agent never ran
the tests."

Check whether the record includes:

- User and assistant turns in order
- Tool calls with arguments, and their results
- File reads and writes, distinguishably
- Command invocations with exit status
- Context compaction or truncation events
- Token or duration accounting

For every category the transcript lacks, mark the dependent signals
**not-measurable** for this session. Do not mark them clean and do not mark them
observed. A signal that had no chance to appear is unmeasured, not absent — this
distinction is what keeps the accumulated store honest, because otherwise a
harness upgrade looks like a codebase regression.

## Step 2: Split into episodes

Friction is per-task, not per-session. A session containing four objectives that
each hit the same wall is four observations, not one — and a session where the
user changed direction three times isn't four times as much evidence.

An episode starts when a new objective is introduced and ends when it's resolved,
abandoned, or replaced. Corrections and follow-ups on the same objective stay
inside it. Pure conversation with no objective is not an episode. When unsure
whether something is one episode or two, treat it as one.

## Step 3: Detect signals

Walk each episode against the catalogue in `references/signals.md`. For each
signal, record one of three dispositions:

- **`observed`** — the friction occurred, with evidence in the transcript
- **`clean`** — the opportunity existed and the friction did not occur
- **`not-applicable`** — no opportunity in this episode

**Recording `clean` is not optional and is the part everyone skips.** Without it
there's no denominator, so you can't tell a fixed problem from one that simply
didn't come up this week. It's also the only way to ever close a finding with
evidence rather than assumption.

## Step 4: Quantify and locate

Two things turn a signal into something rankable.

**Cost.** Count what was actually wasted: tool calls that contributed nothing,
files read and never used, turns spent recovering. Estimate tokens where the
transcript supports it. This is the measurement that static analysis cannot
produce, and it's what lets consolidation rank by real cost rather than by
someone's severity guess.

**Fingerprint.** Resolve the friction to `<lens>:<path>:<symbol>`, matching the
lens contract used by the weekly audit. A signal that can't be resolved to a
location isn't actionable — record it with a null fingerprint for the cost
totals, but it will never become a finding.

## Step 5: Emit observations

Write one record per signal per episode, in the format in
`references/store-and-consolidation.md`.

**Store findings, never content.** Paths and mechanisms, yes. User prose, code
bodies, log contents, command output, credentials — no. These records get read
into agent context weekly and can end up quoted in issues. A transcript is the
single most sensitive artifact in the system, and a friction store that copies
from it inherits every secret the session touched.

Write your own sentence describing the mechanism. Not an excerpt.

---

## What good output looks like

```
Episode 2 — navigability

observed  naming:app/server/models.py:QueryRequest
  Four search terms tried before the type was located; the first three each
  returned enough unrelated hits to be unusable, and the agent fell back to
  reading files.
  cost: 7 tool calls, 4 files read and unused, ~18k tokens

clean     structure:app/server:entry-point
  The service entry point was identified on the first directory listing.

not-applicable  verification:*
  No test infrastructure present; nothing to verify against.
```

Three dispositions, evidence for the first, a measured cost, and a location.

---

## What not to do

**Don't report on the agent's competence.** Covered above, and it's the failure
this skill is most likely to fall into.

**Don't file issues.** One session is not a pattern. Consolidation applies the
threshold.

**Don't infer friction from duration alone.** A long run on a hard task isn't
friction. The evidence has to be a specific wasted action.

**Don't treat every exploration as waste.** Some reading is how work gets done.
Waste is specifically: read, then never referenced, never edited, never cited in
what followed.

**Don't count the same friction twice within an episode.** An unsearchable name
hit four times in one episode is one observation with a cost of four, not four
observations — otherwise a single bad session dominates the ranking.
