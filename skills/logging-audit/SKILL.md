---
name: logging-audit
description: Audit code for logging and observability quality, retrofit code onto whatever logger a repo already uses, and diagnose why a failed run left no usable evidence. Use this whenever reviewing a diff or PR for log quality, cleaning up or standardising logging in a module, judging whether error handling would actually be diagnosable in production, deciding what a catch block should do, or running a postmortem on a job or agent run that failed without explaining itself. Works in any language and any repo. Trigger it for requests like "review the logging here", "why was this run impossible to debug", "is this catch block okay", "make this failure easier to trace", or any investigation of a job that died silently — even when the user never says the word "logging".
---

# Logging audit

Judge whether code produces evidence that makes failures diagnosable, and fix it
where it doesn't.

Two tests sit behind every judgment below, one per audience.

**Human:** could someone reconstruct what happened from the log alone, without
rerunning anything? Many failures can't be reproduced — non-deterministic jobs,
transient upstream errors, conditions that existed for one minute in production.
For those, the log is the only evidence that will ever exist.

**Agent:** does this output narrow where a coding agent has to look? An agent
running a command sees only what that command prints. Output naming the operation
and the code path that failed cuts the search from every file in the repo to a
handful. Code that works correctly but prints nothing is opaque to an agent even
though it has no bug — a distinct defect class, and an increasingly expensive one.

The tests usually agree. Where they diverge, `references/agent-readable.md` covers
the trade-off.

This skill assumes nothing about the repo. Detect what's there, audit against it,
and propose changes that fit the codebase rather than an ideal.

---

## Step 1: Detect the convention

Do this before forming any opinion. Auditing against a general best practice
produces findings that don't get merged; auditing against the repo's own
prevailing pattern produces findings that do.

**Find the logger.** Grep imports for the usual suspects — `pino`, `winston`,
`bunyan`, `zap`, `zerolog`, `log/slog`, `structlog`, `logging`, `tracing`,
`log4j`, `slf4j`, `serilog` — and for a house wrapper (`internal/log`,
`lib/logger`, `@company/logger`). A wrapper is the strongest signal available:
someone already decided how this repo logs, and findings should route through it.

**Sample real usage.** Read 5–10 actual log call sites, weighted toward error
paths. You're looking for the de facto contract: which fields recur, what the
levels mean here, whether messages are structured or prose, whether there's a
correlation id and what it's called.

**Look for a written standard** — `docs/logging.md`, `CONTRIBUTING.md`,
`AGENTS.md`, `CLAUDE.md`, or a package README. If one exists it wins over
inferred usage, but check whether the code actually follows it; a standard the
code ignores is itself a finding.

**Identify the runtime**, because it determines what "correct" means:

| Signal | Load |
|---|---|
| `.github/workflows/` | `references/github-actions.md` |
| `Dockerfile`, k8s manifests, `serverless.yml`, Lambda handlers | `references/containers.md` |
| Plain CLI or library | Neither — stdout/stderr conventions apply as-is |

Load at most one runtime reference. If nothing matches, don't guess.

**Additionally load `references/agent-readable.md`** when coding agents run this
code — signalled by `CLAUDE.md`, `AGENTS.md`, `.claude/`, `.cursor/`, or dev
scripts written to be invoked by an agent. This is orthogonal to the runtime, so
it stacks with either file above.

**If there's no standard and no consistent pattern**, note it as a finding and
audit for internal consistency anyway. Don't stop and demand a standard first —
that turns a useful tool into a refusal. Offer `references/template.md` at the
end if the repo looks like it would benefit, localized to its actual stack.

---

## Step 2: Pick the mode

**Diff audit** — a PR or branch. Review changed lines only. Untouched code around
them is out of scope however tempting; scope creep is why review comments get
ignored.

**Retrofit** — a file or module being cleaned up. Whole file in scope. Preserve
behaviour exactly; a migration that also changes control flow is a different PR.

**Postmortem** — a failed run, job, or CI log. Work backwards from the evidence
that was missing. This is the strongest mode because it's anchored to a real
failure rather than speculation about hypothetical ones. See Step 5.

---

## Step 3: What to look for

Ordered by damage done. Skip anything the repo's linter or type system already
blocks — re-reporting mechanically-caught issues is noise that buries the
findings only a reader can make.

### Blocking

**Secret exposure.** Tokens, keys, auth headers, credential-bearing request
bodies, personal data. Watch the indirect paths, which is where this actually
happens: logging a whole config object, a whole error that embeds the request
that caused it, a URL with credentials in the userinfo, or a stack trace carrying
arguments. Platform redaction only matches exact registered values — anything
derived, truncated, or reformatted goes straight through.

**Swallowed failures.** A catch that neither logs nor rethrows. In shell,
`2>/dev/null || true`, which makes a real failure indistinguishable from the
benign case the line was written to tolerate. Ask what a reader would see if this
path were hit in production. If the answer is "nothing", it's blocking.

**Lost output.** Buffered writes discarded on a crash path; abrupt process
termination with output still queued; logs written to a stream nothing collects.
The runtime reference file covers the specific mechanisms — they differ enough
between environments that a generic rule would be wrong.

**Failure states with no observable record.** A path that can fail while
producing no error, no non-zero exit, and no distinguishing log line. The reader
can't tell a crash from a clean no-op, which is the worst possible ambiguity.

**Errors that cross a boundary without a trace.** A handler that catches, returns
an error response to its caller, and logs nothing server-side. The failure is
visible only to whoever received the response — often a browser, sometimes
nobody. Anyone debugging from the service side sees a clean log and a working
system. Check this specifically at API handlers, RPC boundaries, and job entry
points; it's the most common way a service ends up undebuggable while looking
healthy.

### Worth fixing

**Errors without identifiers.** A message saying something broke, without saying
*which* record, user, tenant, request, or attempt. Include the fields someone
would filter on. Logging `err.message` alone discards the stack and any wrapped
cause — pass the caught value and let the logger serialise it.

**Whole objects logged for visibility's sake.** Printing full request bodies,
response payloads, config objects, or model inputs. This usually arrives with
good intent — making success paths observable, giving an agent more to work with —
and it's the most common route to logging credentials and personal data by
accident. Log the fields that identify and the fields that decide; not the
envelope.

**Wrong level.** Handled, expected conditions logged at `error`, which makes
searching for errors useless. Or genuine failures logged at `info`, which hides
them. Both erode the level system until nobody trusts it.

**Messages that restate the code.** `log.info("starting loop")` tells a reader
what the source already tells them. Log what source can't: inputs, counts,
durations, decisions taken and the reason.

**Missing correlation.** No request, run, or trace id, so lines can't be tied
together within a run or across services. Check whether the repo already has one
and this site just doesn't pass it.

**Retry loops with indistinguishable attempts.** If attempt 2's output looks
identical to attempt 1's, nobody can tell whether the retry helped, and the two
sets of evidence interleave beyond use.

**Logging in a hot path with no sampling.** Per-iteration logging inside a large
loop buries everything around it and can dominate runtime.

### Optional

**Redundant logging at multiple frames.** The same failure logged on the way up
at every level. Log once, at the frame that handles it; add context and rethrow
elsewhere.

---

## Step 4: Report

Findings only. No summary of what the code does — the reader wrote it.

```
### Blocking

**`src/sync.ts:42`** — API key reaches the log via the spread config object.
Platform redaction won't catch it; the value is reassembled from parts.

    - log.info({ op: "sync", ...config });
    + log.info({ op: "sync", endpoint: config.endpoint, keyPresent: !!config.key });

### Worth fixing

**`src/sync.ts:88`** — Failure identifies the operation but not the record, so a
reader can't tell which of 400 items failed or retry it.

    - log.error({ op: "sync", err });
    + log.error({ op: "sync", err, recordId: record.id, attempt });
```

Match the repo's own logger and field names in every suggested fix. A patch that
introduces a different logging style than its neighbours won't merge, no matter
how sound the underlying point.

Every finding needs a location, a reason grounded in what a reader would be
unable to do, and a concrete fix. A finding without a fix is a complaint.

If there's nothing to report, say so plainly. Manufacturing findings to justify
the pass is how a review process loses credibility — and once people skim it, the
real findings get skimmed too.

---

## Step 5: Postmortem mode

Given a failed run's output:

1. **Where does the evidence stop?** The last line before the failure usually
   points at the gap — either the code went silent there, or the output was
   truncated after it.
2. **Is truncation the explanation?** Output ending mid-line, or ending cleanly
   with no error and no result, suggests lost buffered writes rather than silent
   success. The runtime reference covers how this happens in that environment.
3. **What single line would have made this obvious?** That's the fix. Propose it
   at the exact site.
4. **Is the gap systemic?** Check two or three sibling call sites. If the same
   gap is everywhere, propose the shared fix — a wrapper change, a lint rule, a
   type signature — rather than patching one site.

---

## A note on fixes that hold

Prefer changing a signature over adding a rule people must remember. If the house
logger's error method requires the caught error and an operation name, no
reviewer ever has to ask for them again. If it's a convention in a document, it
decays.

When a finding recurs across many sites, the right output is usually one change
to shared code plus a lint rule, not fifty individual patches. Say so rather than
producing the fifty.
