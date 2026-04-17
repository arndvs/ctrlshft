---
name: code-review
description: "Focused review of staged or recent changes to find edge cases, logic errors, and integration risks before merging. Use when asked to 'do a code review', 'review my changes', 'review this PR', 'check my diff', 'review staged changes', or 'pre-merge review'."
---

# Code Review

Output "Read Code Review skill." to chat to acknowledge you read this file.

You are a senior engineer doing a pre-merge code review. Your job is not to audit the full codebase — it is to read what changed and ask: _what could go wrong with this specific set of changes?_

The codebase audit skill finds problems that exist. This skill finds problems that are about to be introduced, or that the change assumes are not problems but are.

---

## What to Review

Review only the diff. This could be:

- **Staged changes** — run `git diff --staged` to get them
- **Unstaged changes** — run `git diff` to get them
- **A specific commit or branch** — run `git diff main...HEAD` or `git log -p -1`
- **Files dragged into chat** — review what's provided
- **A PR description + diff** — pasted inline

If no changes are provided, run `git diff --staged` and `git diff` to find them. If the working tree is clean, run `git log --oneline -5` and ask the user which commit to review.

Before reporting findings, assess the blast radius of the change using the **explore** skill — but selectively. Explore is expensive; only invoke it when the change has real propagation risk.

**Trigger explore when the diff:**

- Modifies a shared utility, helper, or hook used in multiple places
- Changes the shape of a type, schema, or data structure
- Alters an exported function's signature, return value, or side effects
- Adds or changes assumptions about config, env vars, or external state
- Writes to shared state, cache, or database in a new way

**Skip explore when:**

- The change adds a brand new file with no existing callers
- The modification is purely additive (new optional param, new export alongside existing ones)
- The changed function is internal-only with a single known call site visible in the diff

When exploring, focus the sub-agent narrowly: "explore all call sites of `useAuthToken`" not "explore the auth module." Synthesize findings into the Integration Risks section — that's where blast radius lives.

---

## Review Process

### 1. Orient

Before reporting anything, answer these questions internally:

- What is this change trying to do? (Read commit messages and PR description if available)
- What existing behavior does it touch?
- What is the happy path this author had in mind?

### 2. Stress-test the change

Walk through the change with adversarial inputs and unexpected states:

- **Null / undefined / empty** — what happens when a key value is missing?
- **Wrong types** — what if a string comes in where a number is expected?
- **Empty arrays / zero counts** — does math or iteration break?
- **Concurrent calls** — can this be called twice before resolving?
- **Out-of-order execution** — is there an assumption about sequencing that could fail?
- **Large inputs** — does this degrade at scale (N+1, deep recursion, unbounded loops)?
- **Error paths** — does the error handling actually cover the failure modes introduced?
- **State mutations** — does a change mutate shared state in a way that affects callers?
- **New dependencies** — does this change add an assumption about environment, config, or external state that isn't guaranteed?

### 3. Check integration points

For each function, API, or module the change touches or calls:

- Does the change preserve the contract the caller expects?
- Does it introduce a new assumption the callee doesn't guarantee?
- Does it change a return shape, error behavior, or side effect that callers depend on?

---

## Output Format

Start with a **one-paragraph summary** of what the change does and your overall assessment (looks solid, one concern to address, needs rework, etc.). This is the TL;DR a reviewer reads first.

Then report findings grouped as follows. Only include sections with actual findings — omit empty sections entirely.

---

### 🔴 Must fix before merging

Issues that will cause bugs, data loss, or broken behavior in production.

```
[file:line] — What breaks and the exact scenario that triggers it.
→ Fix: What to do instead (be specific).
```

---

### 🟡 Edge cases worth handling

Inputs or states the code doesn't handle that are plausible in production. May not be bugs today but will be.

```
[file:line] — The scenario and what currently happens vs. what should happen.
→ Suggestion: How to guard against it.
```

---

### 🔵 Integration risks

Places where this change's assumptions about callers, callees, or shared state could cause problems in connected code.

```
[file:line] — What assumption is being made and where it could be violated.
→ Worth checking: What to verify before shipping.
```

---

### ⚪ Nits (optional, low priority)

Small things the author may want to know but that don't block the merge. Only include if genuinely worth mentioning — do not pad. This section should usually be short or absent.

```
[file:line] — The observation (one line).
```

---

## Rules

- **Review only the diff.** Do not audit the rest of the codebase unless a change touches something that requires understanding call sites.
- **Every finding needs a file and line reference.** No vague observations.
- **Every Must Fix needs a concrete suggested fix.** Not "handle this case" — what does handling it look like?
- **Do not report style or formatting issues.** Those belong in a linter, not a code review.
- **Do not report missing docs or comments.**
- **Do not surface theoretical risks that require an unlikely chain of failures.** Only report plausible production scenarios.
- **If the diff is clean, say so.** Do not manufacture findings to fill sections.
- **The summary paragraph is not optional.** It's the most useful part of the review for the author.

---

## Handoff

After presenting findings, if there are Must Fix or Edge Case items, offer:

1. `/tdd` — write failing tests that cover the edge cases found before fixing them
2. `/do-work` — fix the Must Fix items directly3.
3. `/grill-me` — ask more questions to clarify the change and find any missing edge cases before fixing
