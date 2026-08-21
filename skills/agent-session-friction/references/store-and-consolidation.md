# Observation store and consolidation

How friction observations are recorded, where they live, and how they become
candidate findings.

## Record format

One JSON object per signal per episode:

```json
{
  "schema": 1,
  "recorded_at": "2026-08-20T14:22:00Z",
  "session_ref": "a3f9c1",
  "episode": 2,
  "harness": "claude-code",
  "lens": "naming",
  "signal": "search-churn",
  "disposition": "observed",
  "fingerprint": "naming:app/server/models.py:QueryRequest",
  "cost": {
    "tool_calls": 7,
    "files_read_unused": 4,
    "turns": 2,
    "tokens_estimate": 18000
  },
  "statement": "Four search terms tried before the type was located; the first three returned enough unrelated hits to be unusable.",
  "confidence": "high"
}
```

**`disposition`** is `observed`, `clean`, or `not-applicable`.

`clean` records carry a fingerprint where one applies and a zeroed cost. They
exist to provide the denominator. Skip them and you lose the ability to
distinguish a fixed problem from one that didn't come up.

`not-applicable` records carry a null fingerprint and exist so that a missing
capability doesn't read as a clean bill of health later.

**`session_ref`** is an opaque short hash. Not a path, not a title, nothing that
identifies the work.

**`statement`** is your own sentence about the mechanism, 40–280 characters. Never
an excerpt. No code, no user prose, no command output, no credentials, no
identifiers beyond the path already in the fingerprint.

## Storage layout

```
.friction/
  2026-08-20-a3f9c1.jsonl      one file per session
  2026-08-19-7b2e04.jsonl
  archive/
    2026-07.jsonl              consolidated and compacted monthly
```

**One file per session, never a shared append target.** Two sessions appending to
one file conflict on merge; separate files never do. This matters more than it
sounds — a friction store that causes merge conflicts gets deleted within a
month.

Committed to the repo, following the same logic as any other agent asset: visible
in review, diffable, and travelling with the code it describes. Add `.friction/`
to whatever ignores generated content from agent context on ordinary tasks — it's
input to the weekly job, not to feature work.

## Consolidation

Run by the weekly audit before the lens agent starts. It reads every observation,
groups by fingerprint, and produces ranked candidates.

**Per fingerprint:**

- `observed_count` — episodes where friction occurred
- `clean_count` — episodes where the opportunity existed and it didn't
- `friction_rate` = observed / (observed + clean)
- `total_cost` — summed across observed records
- `first_seen`, `last_seen`
- `distinct_sessions` — observed count deduplicated by session

**Promotion threshold:** three or more observed occurrences across at least two
distinct sessions. Three occurrences make a pattern; requiring two sessions stops
one bad afternoon from generating findings.

**Ranking:** by total cost, not by frequency and not by severity. A fingerprint
hit twice at enormous cost outranks one hit nine times cheaply. This is the whole
advantage over static analysis — the ranking is measured rather than guessed.

**Suppression:** the same known-fingerprints file the weekly audit already
consumes. Candidates already filed, fixed, or declined are dropped before the
lens agent sees them.

## Resolution detection

The reason `clean` records are mandatory.

A fingerprint with prior observations and a run of consecutive `clean` records —
five or more, across at least two sessions, with nothing observed since — is
**resolved by evidence**. Not "we merged a PR and assume it worked": the friction
measurably stopped happening.

That closes the loop nobody normally closes. It also catches the opposite case:
a fingerprint marked fixed in a prior issue that starts producing `observed`
records again is a **regression**, and worth filing at higher severity than a
fresh finding, because something undid a change someone deliberately made.

## Feeding the lens agent

Consolidation emits:

```json
{
  "candidates": [
    {
      "fingerprint": "naming:app/server/models.py:QueryRequest",
      "lens": "naming",
      "observed_count": 9,
      "clean_count": 2,
      "friction_rate": 0.82,
      "distinct_sessions": 6,
      "total_cost": { "tool_calls": 61, "tokens_estimate": 154000 },
      "first_seen": "2026-07-30",
      "last_seen": "2026-08-19",
      "statements": ["…", "…"]
    }
  ],
  "resolved": [ { "fingerprint": "…", "clean_streak": 7 } ],
  "regressions": [ { "fingerprint": "…", "observed_since_fix": 3 } ],
  "below_threshold": 14,
  "suppressed": 6
}
```

The lens agent's job changes shape given this. It no longer hunts for problems —
it takes ranked candidates with evidence and writes each up as an actionable
brief: exact paths, the change, what's out of scope, how to verify. Cheaper,
better grounded, and far less prone to the enumeration drift that scheduled
scanning produces.

Static lens passes still have a place for anything friction can't see: a badly
named module nobody has touched yet generates no observations. Run both, and
weight the evidence-backed candidates first.

## Retention

Growth is warned about, not automatically compacted. The consolidator reports
store size and warns past roughly 300 session files or 20MB.

Compaction is deliberately unimplemented: the growth rate isn't known until the
store has run for a while, and a scheme designed before there's data compacts the
wrong things. When the warning fires, compact into `archive/` keeping
per-fingerprint aggregates and dropping individual records — trend and totals are
what matter, not full history.

## The one metric worth watching

Consolidation emits a weekly `trend`: friction cost per episode.

This is the number that says whether the whole system works. If the audits and
the implementer are doing their job, it declines. It's derived from collected
data rather than self-reported, and — unlike an attempts-based target — it can't
be improved by accepting worse output. Lowering it requires actually fixing
things.

Deliberately just one number. A dashboard of agentic KPIs invites optimising the
measure; a single cost trend, read occasionally, is enough to notice the system
has stopped working.
