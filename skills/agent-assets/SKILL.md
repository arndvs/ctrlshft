---
name: agent-assets
description: Audit the agentic infrastructure committed to a repo — reusable commands, autonomous workflows, vendored documentation, and tool or MCP configuration — and propose what to add, consolidate, or retire. Use when the same prompt is being retyped across sessions, when agent workflows exist but nobody can tell whether they ran or what they did, when orientation files have gone stale or contradict the code, when agents repeatedly fetch the same external docs, or when planning to move work from interactive prompting to scheduled autonomous runs. Also use for requests like "what should be a slash command", "review our .claude directory", "why do our agent workflows keep silently failing", or "audit our AGENTS.md".
---

# Agent assets audit

Everything an agent needs that isn't application code: the reusable commands, the
scheduled workflows, the vendored reference material, the tool configuration, the
orientation files. These accumulate without anyone owning them, drift out of sync
with the code, and fail quietly.

The question throughout: **is the knowledge that makes agents effective here
committed and current, or is it in someone's terminal history?** A prompt that
works but gets retyped each time is not an asset. Neither is a workflow that runs
nightly and produces nothing anyone reads.

Related skills: `agent-navigability` covers whether the code is legible,
`agent-testability` whether work can be verified, `logging-audit` whether runtime
output is usable. This one covers the scaffolding around all three.

---

## Step 1: Inventory what's there

Look for these, and note their absence as readily as their contents:

- `.claude/commands/`, `.cursor/rules/`, or equivalent reusable prompts
- `CLAUDE.md`, `AGENTS.md`, and any subsystem-level equivalents
- Vendored documentation — `ai_docs/`, `docs/vendor/`
- Agent workflows in CI, and the scripts they call
- MCP or tool configuration, and whether it's committed or per-developer
- Committed plans or specs, and whether the code reflects them

Then the check that finds the most: **open each one and ask whether it still
describes this repo.** Stale assets are worse than missing ones — they produce
confident wrong work, and they survive because nothing fails when they rot.

## Step 2: Find what should be an asset but isn't

The inventory tells you what exists. This step tells you what's missing, and it's
where most findings come from.

Look at recent history for repeated manual work:

- Shell history, README instructions, or CI steps describing multi-step sequences
- The same setup or verification incantation in several places
- Long prose instructions pasted into PR descriptions or issues
- Anything documented as "run these four commands in order"

**Three occurrences make a pattern.** A sequence run three times should be a
committed command — not because typing is slow, but because a committed command
is identical every run, reviewable in a PR, and fixable in one place. Retyped
prose drifts, and the drift is invisible until something fails oddly.

---

## Step 3: What to look for

### Blocking

**Workflows that can fail silently.** A scheduled agent run that catches its own
errors and exits zero, discards logs, or writes results nowhere. Nobody notices
it stopped working — often for months. The signal is `|| true`, a bare `exit 0`
after a failure branch, or no artifact upload.

**Assets that contradict the code.** An `AGENTS.md` naming directories that no
longer exist, a command referencing a deleted script, vendored docs for a version
you've since upgraded past. Each produces confident wrong work, which costs more
than having nothing.

**Secrets or environment specifics committed in assets.** Commands with tokens
inline, MCP config carrying credentials, docs containing real connection strings.
Assets get read wholesale into context and often into a model provider's logs.

### Worth fixing

**Repeated prompts that aren't commands.** From Step 2. The fix is to commit the
literal text that worked — not a generalised version. Parameterise on the second
use case, once you know what actually varies.

**Orientation files that have grown into manuals.** Length is the signal. A
`CLAUDE.md` past a page or so is competing with the task for context on every
session. Worse, when it needs a section explaining which of several similar
directories is real, the finding is the directories, not the file.

**Aspirational conventions.** Assets describing how the team wishes the code
worked. An agent follows them and produces changes inconsistent with everything
around them. Either fix the code or fix the file — not neither.

**Missing do-not-touch guidance.** Generated files, vendored code, deprecated
paths. Without this, agents make careful edits to files overwritten on the next
build. Cheap to add, prevents a distinctive and expensive failure.

**Unversioned vendored docs.** Local copies with no note of version or fetch
date. They look authoritative and go stale invisibly. Either record both or
delete them.

**Workflows with no observable output.** Runs that leave no artifact, no summary,
no issue. Even a successful one teaches nobody anything, and a failed one can't
be reconstructed.

**Per-developer tool configuration.** MCP servers or tool setups that live in
personal config rather than the repo, so agent capability varies by whose machine
it runs on. Results become irreproducible.

### Optional

**Command sprawl.** Many near-identical commands where a parameter would do.
Minor, but it makes choosing harder for both agents and people.

**Unused assets.** Commands nobody runs, workflows disabled months ago. Retire
them; they're read and considered on every session that lists the directory.

---

## Step 4: Report

Lead with what the gap costs.

```
### Blocking

**`.github/workflows/nightly-review.yml`** — the agent step ends with
`|| echo "agent likely crashed"` and exits zero. The workflow has reported
success on every run for four months; the artifact upload was removed in March,
so there's no way to tell how many actually produced anything.

Persist per-attempt logs and let a failed run fail.

### Worth fixing

**`scripts/start.sh` plus three README steps** are pasted into sessions
repeatedly. Commit as `.claude/commands/start.md` with the literal text —
generalise later if a second variant appears.
```

Every finding needs a location, the cost, and a fix. "Should have more commands"
is not a finding. "This four-step sequence appears in the README, CI, and two
issues, and drifts between them" is.

**Sequence by cost of the gap, not by how easy the asset is to write.** A silently
failing workflow outranks a missing command, even though the command takes two
minutes and the workflow fix takes an hour.

If the assets are current and the workflows are observable, say so. Adding
commands nobody needs makes the directory harder to search — the same cost as
any other clutter.

---

## A note on sequencing

Assets are the cheapest of the four skills to act on and the easiest to
over-apply. They don't fix anything structural: a command that wraps a confusing
setup makes it repeatable, not simple, and an `AGENTS.md` explaining an ambiguous
layout is a workaround with maintenance cost.

So when a finding here exists because the underlying code is hard to work with,
say that plainly and propose the asset as the interim step. The asset buys time;
it doesn't close the finding.
