---
name: compliance-audit
description: "Auto-invoke after any do-work, tdd, systematic-debugging, or review-pr-copilot task completes to review the diff against active rules and skills, flag violations, update the skill if a gap is found, and close the loop between 'rule was loaded' and 'rule was followed'."
---

# Compliance Audit

Output "Read Compliance Audit skill." to chat to acknowledge you read this file.

Runs after a task completes. Reviews the actual diff against the rules and skills that were active during the session. Flags violations explicitly. Updates the skill if the gap is structural.

This skill exists because "Read X" confirms a rule was loaded into context — not that it was followed. The compliance audit closes that gap.

---

## When to invoke

Auto-invoke after:

- `/do-work` completes and produces a commit
- `/tdd` completes a red-green-refactor cycle
- `systematic-debugging` produces a fix
- `review-pr-copilot` finishes a round (catches self-initiated changes bundled into Copilot-comment commits — see PR #68 dogfood). Specifically check:
  - **HITL tier classification** — any HITL-tier reply that lacks signal arithmetic, or that uses *effort* reasoning ("this would be a lot of work", "bundling risks another round") instead of *subjectivity* reasoning ("the approach itself is ambiguous"). Flag as a tier misclassification — the comment was almost certainly Confirm-tier and got punted into HITL to dodge the work. (Failure mode: PR #50 round 5.)
  - **HITL deferral path** — every HITL-tier reply must either (a) link a filed GitHub issue and have its thread resolved (HITL-deferrable), or (b) explicitly state "HITL-blocking" with a one-sentence reason about why the *approach* is ambiguous. Bare "flagging for review" replies with no issue link and no blocking reason are stranded threads — flag and require the agent to either file an issue or supply the blocking reason. (Failure mode: PR #50 round 5.)

Can also be invoked manually: `/compliance-audit` to review the most recent commit against active context.

---

## Method

### Phase 1 — Gather active context

Before reviewing the diff, establish what rules and skills were in scope.

```bash
# What contexts were active during this session?
echo $ACTIVE_CONTEXTS

# What rule files are currently loaded?
ls ~/dotfiles/rules/

# What skills were explicitly invoked?
# (check the session transcript for "Read X" outputs)
```

Produce a list:

- Active instruction files (from `$ACTIVE_CONTEXTS`)
- Rules files loaded (from `rules/` matching active contexts)
- Skills explicitly invoked during the session

---

### Phase 2 — Get the diff

```bash
# Most recent commit diff
git diff HEAD~1 HEAD

# Or staged changes if not yet committed
git diff --cached
```

---

### Phase 2b — Fetch PR review threads (review-pr-copilot trigger only)

The HITL-tier-classification and HITL-deferral-path checks under the `review-pr-copilot` trigger evaluate **PR thread replies**, not diffs. When auditing a `review-pr-copilot` round you must fetch those threads before scoring.

**Required tools** (MCP tools may be deferred — use `tool_search` if not loaded):

- `github-pull-request_currentActivePullRequest` (preferred, returns thread node IDs)
- `gh api graphql` fallback (CLI command, not an MCP tool — run via terminal when the PR-extension cache is stale)
- `mcp_github_pull_request_read` (method `get_review_comments`) for comment bodies — **degraded mode only** (see below)

**Fetch pattern:**

```bash
gh api graphql -f query='query {
  repository(owner:"<owner>",name:"<repo>"){
    pullRequest(number:<N>){
      reviewThreads(first:50){
        nodes{
          id isResolved
          firstComment: comments(first:1){ nodes{ databaseId path body author{login} } }
          lastComments: comments(last:10){ nodes{ databaseId path body author{login} } }
        }
      }
    }
  }
}'
```

The query aliases two comment windows per thread: `firstComment` (the original Copilot review comment) and `lastComments` (the 10 most recent replies). In practice this covers all review threads — Copilot PRs rarely exceed 50 threads or 10 replies per thread. If a PR does exceed these limits, increase the `first:` / `last:` values or paginate using `pageInfo { hasNextPage endCursor }`. Pair `firstComment.nodes[0]` (Copilot's original) with the latest agent-authored entry in `lastComments` (scan from the end for a comment whose `author.login` matches the PR author or agent). For each thread the agent's reply touches, capture: thread ID, original Copilot comment body, the agent's reply body, and whether the thread is resolved. Pass this set to Phase 3 — the HITL checks key off reply text (presence of arithmetic, presence of effort-vs-subjectivity reasoning, presence of `Filed as #N` link or `HITL-blocking` declaration).

If the PR has no Copilot review threads, the HITL checks are vacuously passed — note "no HITL replies to audit" and continue to the diff-based checks in Phase 3.

**Degraded mode** — if both `currentActivePullRequest` and `gh api graphql` are unavailable (e.g. `gh` CLI not installed), fall back to `mcp_github_pull_request_read` (method `get_review_comments`). This API returns comment bodies but **not** `isResolved` state or GraphQL thread IDs, so the HITL-deferral-path check ("issue link + thread resolved") cannot be fully validated. In degraded mode: check reply bodies for arithmetic and `Filed as #N` links as normal, but mark the resolved-state check as `UNCLEAR — thread resolution not verifiable without GraphQL` and continue to Phase 3.

---

### Phase 3 — Rule-by-rule audit

For each active rule and instruction file:

1. State the rule in one line
2. Check the diff for evidence it was followed
3. Flag any violation explicitly

**Resource management checks (always run when JS/TS files are in the diff):**

When the diff touches `.ts`, `.tsx`, `.js`, or `.jsx` files, always check `rules/resource-management.md` compliance — even if not explicitly listed in active contexts. Specifically scan the diff for:

**Detection — scan for these anti-patterns:**

- `addEventListener` / `.on()` / `.subscribe()` / `.observe()` without cleanup `[PROD]`
- `setInterval` / `setTimeout` / `requestAnimationFrame` without clear/cleanup `[PROD]`
- `new Map()` / `new Set()` / `= {}` / `= []` at module scope without eviction `[PROD]`
- `useEffect` that creates resources without a return cleanup function `[PROD]`
- `fetch()` in components without `AbortController` `[PROD]`
- Database/file/stream `open()` without `close()` in a `finally` block or TC39 `using` `[PROD]`
- Closures capturing large objects in long-lived callbacks `[PROD]`
- Module-scope state without `globalThis.__x ??=` protection (HMR stacking) `[DEV]`
- Large inline data arrays/objects (100+ entries) at module scope instead of loaded from JSON/disk `[DEV]`
- `new SomeSDK()` / `new Client()` created inside functions instead of as a `globalThis`-protected singleton `[BOTH]`
- Build plugin wrappers (`withSentryConfig`, `withBundleAnalyzer`) applied without `NODE_ENV` guard `[DEV]`
- SSE/WebSocket listeners accumulating events without backpressure or consumption bounds `[PROD]`
- `console.log` of large objects (request bodies, datasets, DOM trees) in per-request or render-path code `[DEV]`

Severity: `[PROD]` patterns are **High** — they affect deployed applications. `[DEV]` patterns are **Medium** — they affect developer experience. `[BOTH]` patterns are **High**.

**Fix verification — when the diff contains a fix for any of the above, verify the fix is correct:**

Do NOT mark a violation as resolved unless the fix matches a valid pattern from `rules/resource-management.md`. Common invalid fixes:

| Pattern | Invalid fix | Why it's wrong | Valid fix |
|---------|-------------|----------------|-----------|
| Large inline data | Delete the file/data | Masks the problem, loses functionality | Extract to JSON + lazy accessor with `globalThis` |
| Large inline data | Wrap in function without `globalThis` | Module-scope `let` still duplicates on HMR | `globalThis.__x ??=` lazy accessor |
| Large inline data | Move to separate `.ts` file with `export const` | Same problem, different file | JSON import or `globalThis` accessor |
| SDK per-request | Move to module-scope `const` | Duplicates on HMR (each with own timers/queues) | `globalThis.__client ??= new SDK()` |
| Unbounded Map | Add `.clear()` on a timer | Periodic clearing loses valid data | LRU/TTL eviction or `WeakMap` |
| Missing cleanup | Add mounted-ref check | Outdated React 17 pattern, doesn't cancel work | `AbortController` |

**Fix chaining — verify compound fixes:**

Some patterns require TWO fixes applied together. If only one is applied, flag the gap:

- SDK singleton moved to module scope → also needs `globalThis` for HMR safety
- Unbounded cache given eviction → also needs `globalThis` for HMR safety
- Large data extracted to function → function still needs `globalThis` cache

**Output format per violation:**

```
[RULE] resource-management.md — [section name]
[STATUS] ✗ VIOLATION
[HAZARD] [PROD] / [DEV] / [BOTH]
[EVIDENCE] file:line — description of what was found
[SEVERITY] High / Medium
[REMEDIATION] Correct fix pattern from rules/resource-management.md:
  [one-line code example or reference to specific rule section]
```

**Output format per rule:**

```
[RULE] global.instructions.md — Surgical Changes
[STATUS] ✓ PASS
[EVIDENCE] Only files mentioned in the task were modified. No reformatting of adjacent code.

[RULE] instructions/nextjs.instructions.md — Server Components by default
[STATUS] ✗ VIOLATION
[EVIDENCE] /app/components/UserCard.tsx added "use client" without justification.
           Server component was appropriate here — no client-side interactivity required.
[SEVERITY] Medium — pattern could spread if uncorrected
```

Severity levels:

- **Critical** — security, data integrity, or architectural violation
- **High** — rule broken in a way that will cause bugs or rework
- **Medium** — rule broken but consequence is quality/consistency, not correctness
- **Low** — minor deviation, likely intentional

---

### Phase 4 — Compliance summary

```
COMPLIANCE SUMMARY
──────────────────
Session: [task description]
Commit: [hash]
Rules checked: [n]
Skills checked: [n]

Results:
  ✓ PASS: [n]
  ✗ VIOLATION: [n]
  ⚠ UNCLEAR: [n]  (rule ambiguous — couldn't verify either way)

Violations:
  [list with severity]

Overall: PASS / FAIL / PARTIAL
```

---

### Phase 5 — Skill update (if structural gap found)

If a violation reveals that the active skill or rule doesn't clearly prohibit the behavior, update the skill inline.

**Decision rule:**

- Violation occurred AND the rule/skill was ambiguous → update the skill
- Violation occurred AND the rule/skill was clear → flag as agent non-compliance, no skill update needed
- No violation but rule was ambiguous → clarify the rule anyway

**Update format:**

```markdown
## ⚠ Known failure mode — [date]

**Situation:** [what happened]
**Rule that should have caught it:** [rule name]
**Why it didn't:** [ambiguity / gap in the wording]
**Fix:** [clarified instruction added below]

---
```

Add the fix directly to the relevant section of the skill or rule, not in a separate "known issues" block at the bottom.

---

### Phase 6 — Log entry

Append to `working/logs/compliance-log.md`:

```markdown
## [date] — [task name] — [PASS/FAIL/PARTIAL]

Commit: [hash]
Active contexts: [list]
Violations: [n] ([severity summary])

[brief description of any violations and disposition]
```

Then push the result to the HUD daemon:

```bash
source ~/dotfiles/bin/write-hud-state.sh
update_hud_compliance <pass_count> <fail_count> <warn_count>
```

For each violation found, also emit individual events:

```bash
write_hud_event "fail" "VIOLATION — <rule_file> — <title> — <severity>"
```

This log becomes the stress test baseline and the honest answer to "has this been tested."

---

## Output

The audit produces:

1. A rule-by-rule compliance report in the session transcript
2. Any skill/rule updates applied inline
3. A log entry in `working/logs/compliance-log.md`

The report goes in the session. The log persists across sessions. Over time the log is the empirical record of compliance rate.

---

## Honesty note

This audit cannot catch everything. It reviews the diff against stated rules — it cannot detect subtle semantic violations (e.g., code that technically compiles but violates the spirit of the architecture). The goal is not perfect verification. It's making violations visible and recoverable rather than silent.

The compliance rate over time is the real metric. A system with documented 85% compliance and a known improvement path is more trustworthy than one that claims 100% with no verification.
