# Audience reference: coding agents

Load when coding agents run this code — `CLAUDE.md`, `AGENTS.md`, `.claude/`,
`.cursor/`, or dev scripts written to be invoked by an agent. Stacks with the
runtime reference rather than replacing it.

## The agent is a reader with unusual properties

An agent running a command sees exactly what that command prints, and nothing
else. It can't attach a debugger, watch a UI, or notice that a request looked
slow. Output is the whole channel.

That makes silence a defect even when the code is correct. A handler that
processes a request perfectly and prints nothing gives an agent no way to confirm
it ran, no way to locate the code involved, and nothing to work from when
something downstream breaks. Correct-but-opaque code isn't buggy; it's just
expensive to work on.

Three differences from a human reader drive everything below:

**Fixed context budget.** A human skims a 50,000-line log in seconds and reads
the interesting part. An agent either takes the whole thing into a finite window
or takes none of it. Volume is a hard constraint, not an annoyance.

**No out-of-band knowledge.** A human recognises "the usual timeout" from
experience. An agent has only what's on screen.

**Output narrows the search.** This is the biggest lever. An agent debugging with
no output must consider every file. Output naming the operation and the failing
code path cuts that to a handful. A stack trace is often worth more than a
carefully worded message, because it's a direct index into the code.

## The additional test

Alongside "could a human reconstruct this," ask: **does this output tell an agent
which files to open?** It's a sharper test than it sounds, and it justifies log
lines that look redundant to a human — an operation name and a module path are
obvious to someone who knows the codebase and load-bearing for something that
doesn't.

Where the two tests disagree, they disagree on volume, and volume is where
judgment is needed.

## Volume: full fidelity to a file, curation to stdout

There's a tempting argument that an agent should see *everything*, since any line
might matter and filtering to warnings and errors throws away the story. The
first half is right and the second half doesn't follow.

Warnings-and-errors-only is genuinely too thin — it shows what broke and not what
led there. But "print everything to stdout" fails on any real codebase, because
the output either exhausts the context window or crowds out the reasoning space
the agent needs to actually use it. A 200,000-line log that doesn't fit is worth
less than a 200-line log that does.

The resolution is that these are different sinks:

- **Session log file** — full fidelity, every level, written to a known path. The
  agent greps it or reads the tail on demand. Costs nothing until read.
- **stdout** — the curated stream. Phase boundaries, decisions, warnings, errors
  with stack traces. Sized so a whole run fits comfortably in context.

Recommend this split whenever a repo's stdout is either too sparse for an agent
to work with or too voluminous to fit. It resolves the tension instead of picking
a side. Note that under containers a log file is usually the wrong move — see
`references/containers.md` — so there the answer is level configuration plus
sampling instead.

**When suggesting a session log, check it's discoverable.** A log file the agent
doesn't know about is a log file that doesn't exist. Its path belongs in
`CLAUDE.md` or `AGENTS.md`, not just in the code that writes it.

## The pressure this creates, and the line it must not cross

Making code agent-legible pushes toward logging *more*. That pressure runs
directly into the secrets rule, and the collision has a predictable shape:
someone adds full request and response bodies so the agent can see what happened,
and ships credentials, tokens, and personal data to stdout along with it.

Two things make this worse than ordinary over-logging:

**Stdout may leave the machine.** When an agent reads output, that output enters a
model provider's context. Data that used to reach a log aggregator now reaches an
inference API. Whether that's acceptable is a policy question for the repo's
owners, but it should be a decision rather than a side effect.

**"For the agent" reads as a justification.** It makes an over-broad log line look
purposeful in review, so it survives scrutiny that a bare object dump wouldn't.

The line: log what identifies and what decides — operation, ids, counts,
durations, branch taken and why, full errors with stacks. Not the envelope that
carried them. This costs an agent almost nothing, because identifiers and
control-flow decisions are what narrow the search anyway; payload contents rarely
do.

Treat "logged for agent visibility" as a reason to look harder at a finding, not
a reason to accept it.

## Structured versus readable

Structured JSON is right when a machine queries the logs later. For output an
agent reads inline, plain readable lines are usually better: fewer tokens per
event, and no structure the model has to parse before it can use them.

Where both matter, that's another argument for the two-sink split — JSON to the
file for querying, readable lines to stdout for reading. Don't push a repo toward
JSON on stdout if nothing is actually querying it; it's a real cost for a benefit
that may not exist.

## Exit codes still matter

Agents branch on exit status before reading anything. A command that prints an
error and exits 0 will be treated as successful, and the agent moves on. Flag
this wherever it appears — it's cheap to fix and it silently corrupts every
decision made downstream.
