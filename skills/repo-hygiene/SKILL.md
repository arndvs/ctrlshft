---
name: repo-hygiene
description: "Drives a long-running, incremental refactor of a messy codebase toward reusable layouts, extracted components, and clean structure. Use whenever the task involves auditing a repo for structural debt, planning the next step of a multi-week refactor, or generating a single well-scoped backlog issue for automated/nightly refactor runs. Also use it when asked to clean up huge monolithic pages, extract layouts or components, migrate page CSS to Tailwind, set up a repeating refactor workflow, or 'improve repo hygiene'. Stack-aware: dispatches to Astro, static-HTML, Worker-TS, or Python audits automatically. Trigger even if the user only says 'what should I clean up next' about a project."
---

# Repo Hygiene

Turn a spaghetti codebase into a component-based, well-structured one, one mergeable issue at a time. This is the generalized successor to the Astro-only refactor pilot — it detects the stack and applies the matching audit and phase model.

This skill runs in two modes:

- **Audit mode** — measure the repo, report where it stands, propose the next task. Human reads it.
- **Issue mode** — same analysis, but the output is exactly one GitHub issue, written for a *different* agent to execute later with no access to your reasoning. This is the mode the nightly cron uses.

The output is always **one** task. Not a roadmap, not a batch. The whole design assumes a nightly cadence, so shipping one small correct thing beats proposing five.

## Core principle: the code is the state, the ledger is the memory

Never trust `.refactor/state.json` about what the codebase looks like. It drifts the moment someone merges a hand-written PR. Instead:

- **Ground truth about the code** comes from running `scripts/audit.mjs`, every single run, before deciding anything.
- **The ledger** (`.refactor/state.json`) is only for things the code can't tell you: which tasks were rejected and why, which approaches were tried and reverted, which files are off-limits, the current phase.

When the audit and the ledger disagree about progress, the audit wins and you update the ledger to match. Say so in your output — silent reconciliation hides the fact that someone did work outside the loop.

## Stack detection (do this first)

Before anything else, determine the stack. This decides which audit and which phase model apply. Run the detection in `scripts/audit.mjs` (it emits `stack`), or infer manually:

| Signal | Stack |
|--------|-------|
| `astro.config.*` + `src/pages/*.astro` | `astro` |
| Top-level `*.html` files, no framework, `wrangler pages dev .` | `static-html` |
| `wrangler.toml`/`wrangler.jsonc` + `worker/` or `src/workers/`, no Astro | `worker-ts` |
| `*.py` at root, no `package.json` | `python` |
| None of the above | `generic` |

Each stack has its own phase model in `references/phases-<stack>.md`. Read the one matching the detected stack. If the stack is `generic`, use `references/phases-generic.md` and the generic audit signals.

## Run sequence

Do these in order. Steps 1–3 are cheap; bail out early rather than doing analysis you'll throw away.

### 1. Check for an open task (issue mode only)

Query for open issues with the bot label:

```bash
gh issue list --label repo-hygiene --state open --json number,title,createdAt
```

**If one is open, do not create another.** This is the guard that stops you waking up to thirty issues. Instead:
- Open less than 7 days: exit silently, no output.
- Open 7–14 days: post one comment on the existing issue noting it's stalled and asking whether to re-scope or close. Then exit.
- Open more than 14 days: post a comment proposing the task be split, with a concrete smaller version of it. Then exit.

Never open a second issue to "unblock" the first. A backed-up queue is information — it means tasks are too big, and the fix is smaller tasks, not more of them.

### 2. Run the audit

```bash
node .refactor/audit.mjs --json > /tmp/audit.json
```

Read `references/metrics.md` to interpret the output. The numbers that matter most vary by stack, but the constants are: pages/files without a layout or shared shell, largest file line counts, duplicated markup blocks, and per-phase completion percentages.

### 3. Determine the current phase

Read `references/phases-<stack>.md`. Walk the phases in order and pick the **first** one whose exit criteria are not yet met. That is the current phase, regardless of what the ledger claims.

Phase order is not a suggestion — it's load-bearing. Converting CSS to Tailwind before components are extracted means converting the same markup three times. Extracting components before a layout exists means every component re-implements the page chrome. If you find yourself wanting to skip ahead because a later task "looks easier," that's the signal you've mis-read the exit criteria.

### 4. Pick exactly one task

From the current phase's task pool, pick the highest-value task that fits the size budget:

- Touches **≤ 8 files**
- Changes roughly **≤ 400 lines**
- Sits entirely within **one phase**
- Has **one concern** — structural *or* stylistic, never both

If the obvious next task exceeds budget, split it and take the first slice. "Extract the nav" is a task. "Extract all shared chrome" is a project.

Prefer tasks that unlock other tasks. Extracting a layout that 40 pages will use beats extracting a component used twice, even though both are the same size.

Skip anything in the ledger's `rejected` or `deferred` list unless the audit shows the underlying situation materially changed — and if you propose something previously rejected, say explicitly why the situation changed.

### 5. Write the output

For issue mode, follow `references/issue-template.md` exactly. The template exists because the agent executing this issue will have none of your context — it sees the issue text and the repo, nothing else. Vague issues produce vague PRs.

For audit mode, lead with the phase and the one recommended task, then the supporting numbers.

### 6. Update the ledger

Append the proposed task to `.refactor/state.json` with status `proposed` and the issue number. Commit it in the same run. The schema is in `assets/state.example.json`.

## Task construction rules

These are the difference between an issue a coding agent can execute and one it will botch.

**Name the files.** "Extract the header component" is unactionable. "Extract lines 1–84 of `src/pages/index.astro` into `src/components/SiteHeader.astro`, then replace the same block in the 6 files listed below" is executable.

**State the invariant.** Every structural task carries the same one: rendered output must be byte-identical except for whitespace. Say it every time. It's what makes the task verifiable and it's what stops an agent from "improving things while it's in there."

**Give the verification command.** Usually `npm run build` (or the stack's build), plus a diff of built output against a baseline if Phase 0 set that up. An acceptance criterion nobody can run is a wish.

**Declare what's out of scope.** Explicitly forbid the adjacent temptations: no styling changes during structural passes, no renaming, no dependency bumps, no "while I was here" fixes. Scope creep is the main way these PRs become unreviewable.

**Assume the executing agent is competent but uninformed.** Don't explain what a component is. Do explain which of the four near-identical nav blocks is the canonical one.

## Refactor recipes

`references/recipes.md` has the mechanics for each phase's task types — layout extraction, component extraction, props inference, CSS-to-Tailwind conversion, content collection migration, and the stack-specific variants. Read the section for the current phase before writing the task. The recipes are where the stack-specific judgment lives (slots vs props, when scoped `<style>` should survive, how to handle `is:inline` scripts, when a static-HTML repo should adopt a templating layer) and skipping them produces generically-correct-but-wrong tasks.

## Setting up the automation

If asked to install the loop rather than run it, see `references/setup.md`. Short version: copy `assets/nightly-refactor.yml` into `.github/workflows/`, copy `scripts/audit.mjs` and `assets/state.example.json` into `.refactor/`, and confirm the workflow has `issues: write` permission.

Two things to warn the user about, because both cause silent failure: GitHub cron times are UTC and can be delayed by tens of minutes under load, and scheduled workflows are **disabled automatically after 60 days without repo activity**. Always wire up `workflow_dispatch` alongside the schedule so there's a manual trigger.

## When to stop

When the final phase's exit criteria are met, the loop's job is done. Say so plainly and propose disabling the cron rather than inventing make-work. A refactor bot that runs forever will eventually start churning code for its own sake, and that's worse than leaving it alone.
