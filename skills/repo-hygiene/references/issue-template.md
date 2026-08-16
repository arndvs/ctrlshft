# Issue template

The agent that executes this issue sees the issue body and the repo. Nothing else — not the audit, not your reasoning, not this conversation. Write accordingly.

Use this structure exactly.

---

**Title:** `[hygiene P<phase>] <imperative, specific>`

Good: `[hygiene P2] Extract SiteFooter from 6 pages into src/components/SiteFooter.astro`
Bad: `[hygiene P2] Component cleanup`

**Labels:** `repo-hygiene`, `phase-<n>`

**Body:**

```markdown
## Goal
<One sentence. What the repo looks like after this is merged.>

## Why now
<One or two sentences tying this to the current phase and what it unblocks.
Include the specific audit numbers that motivated it.>

## Files in scope
<Explicit list. Every file that should be touched, with line ranges where
the change is partial. If you can't enumerate the files, the task is too vague
to hand off — split it.>

## Steps
1. <Concrete, ordered, verifiable.>
2. ...

## Out of scope
- <The adjacent temptations, named explicitly.>
- No styling changes (this is a structural task)
- No renaming beyond what's listed
- No dependency changes
- No unrelated fixes noticed along the way — open a separate issue instead

## Acceptance criteria
- [ ] <build/typecheck/test command> passes
- [ ] Rendered output for all routes is unchanged vs the Phase 0 baseline
      (`node .refactor/verify.mjs`)
- [ ] <task-specific criterion, measurable>
- [ ] Net line count reduced by ~<N>

## Verification
```bash
<the runnable verification command>
```

## If you get stuck
<The known ambiguity, if there is one, and the decision rule.
E.g. "Three of the six footers have an extra newsletter form. Extract the
common footer and pass the form as a named slot — do not add a boolean prop.">

## Rollback
Revert the PR. No migrations, no data changes, no config changes outside
those listed above.
```

---

## Rules for filling it in

**The "Why now" section is not decoration.** It's how a human reviewer decides whether the bot is still on track, and it's the first thing to look at when the loop starts producing junk. Always include real numbers from the audit.

**"If you get stuck" is where the value concentrates.** You did the analysis; you know which of the four nav variants is canonical, which page has the weird inline script, which duplicate is actually different. Write down the thing that would otherwise cost the executing agent twenty minutes and a wrong guess. If the task has no ambiguity, omit the section rather than padding it.

**Acceptance criteria must be runnable.** "Code is cleaner" is not a criterion. "No file in `src/pages/` exceeds 300 lines" is, because `audit.mjs` checks it.

**Estimate the line delta.** It's a cheap sanity check on scope — if your estimate exceeds 400, you already know to split before anyone starts work.
