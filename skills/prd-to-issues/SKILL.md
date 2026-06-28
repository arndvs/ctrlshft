---
name: prd-to-issues
description: "Break a PRD into independently grabbable GitHub issues with dependency relationships. Use when asked to 'break this PRD into issues', 'create issues from PRD', 'plan the work', 'create a kanban', or after writing a PRD to prepare work for execution."
---

# PRD to Issues

Output "Read PRD to Issues skill." to chat to acknowledge you read this file.

Pipeline position: `/grill-me` → `/write-a-prd` → `/architect` → **`/prd-to-issues`** → `/do-work` → `shft`

Use this skill to create GitHub issues from a finalized PRD or plan. Use `/architect` for deeper analysis and planning before issue creation.

## Process

1. **Locate the PRD** — find the PRD wherever it exists (GitHub issue, local file, or in the conversation).

2. **Explore the codebase** — understand the existing architecture, conventions, and relevant code paths needed to break the work into slices.

3. **Draft vertical slices** — break the PRD into tracer bullets (vertical slices). Each slice should wire through all layers end-to-end rather than building horizontally (all backend → all UI → all routes). Phase 1 should always be the simplest possible end-to-end wiring.

4. **Categorize each slice:**
   - **AFK** — can be implemented and PR-opened autonomously. Merging stays a human gate (someone applies `agent:merge`); "AFK" does **not** mean auto-merged. Prefer AFK where possible.
   - **Human-in-the-loop (HITL)** — requires human interaction such as an architectural decision, design review, or taste judgment, before or during implementation.

5. **Create a QA issue** — always create a final issue with a detailed manual QA plan for all items that require human verification. This is the last issue in the dependency chain.

6. **Quiz the user** — present the proposed breakdown and ask:
   - Does the granularity feel right?
   - Are the dependency relationships correct?
   - Should any slices be split further?
   - Are the correct slices marked as HITL vs AFK?

7. **Create GitHub issues** — create them as **independent issues** (not sub-issues — see *Native dependencies* below), then wire labels and dependencies so they enter the Sandcastle pipeline.

   **a. Bodies** — generate each issue from the template below. Pass bodies via `--body-file` (a temp file, or `--body-file -` from a quoted here-doc `<<'EOF'`) or the GitHub MCP `mcp_github_issue_write` (method `create_issue`, no shell escaping). Do **not** put Markdown bodies with backticks in unquoted shell variables or here-docs — the shell executes command substitutions and corrupts the body.

   **b. Pipeline labels** — this is how the issues actually enter the pipeline (full contract: `instructions/sandcastle-pipeline.instructions.md`):
   - First **unblocked AFK** slice → `Sandcastle` (starts review → plan → implement → PR autonomously).
   - Other **AFK** slices that have blockers → `agent:queued` (`agent-promote-queued` flips them to `agent:implement` when their blockers close).
   - **HITL** slices, and any unblocked-but-not-first AFK slice → no pipeline label (a human starts them).

   `agent:queued` only auto-releases when a *blocker closes*, so an unblocked slice can't be queued — nothing would release it. Give exactly one unblocked slice the `Sandcastle` start and leave other unblocked ones unlabeled to bound the blast radius (N `Sandcastle` labels = N concurrent agent runs against the proxy). You run locally with your own `gh` PAT, so labels you apply **do** trigger workflows — inside a workflow, label writes need `AGENT_PAT` because `GITHUB_TOKEN`-applied labels don't re-trigger.

   **c. Native dependencies** — encode "blocked by" as **native GitHub issue dependencies**, never body text. `agent-promote-queued` reads the native `blockedBy`/`blocking` relation and **refuses sub-issues** (hence independent issues, not children). Add each edge with the blocking issue's **REST numeric id** (`gh api repos/$OWNER/$REPO/issues/N --jq .id` — *not* `gh issue view --json id`, which returns the GraphQL node id), never its issue number:

   ```bash
   # $DEP blocked_by $BLOCKER  (issue_id = the blocking issue's DB id)
   MSYS_NO_PATHCONV=1 gh api -X POST "repos/$OWNER/$REPO/issues/$DEP/dependencies/blocked_by" -F issue_id="$BLOCKER_DB_ID"
   ```

   The `**Blocked by:** #N` line in the template is human-readable only — the native edge is what the automation reads.

```markdown
# [Slice Title]

**Type:** AFK | HITL
**Parent PRD:** #[issue-number]
**Blocked by:** #[issue-number], #[issue-number]

## Description

[What this slice accomplishes end-to-end]

## Acceptance Criteria

- [ ] [Specific, testable criteria]
```

## Pipeline handoff

The created issues plug into the Sandcastle label state machine — full contract in
`instructions/sandcastle-pipeline.instructions.md`. In short: `Sandcastle` on the first AFK slice
starts the autonomous chain (review → plan → implement → PR); `agent:queued` + native deps let
`agent-promote-queued` release dependents as blockers close; and **merge stays a human gate**
(`agent:merge`) at the end of every PR. HITL slices wait for a human to apply `Sandcastle`.

## Handoff

After issues are created, offer:

1. `/do-work` — start implementing the first slice
2. **Save plan to `working/`** — if context is high or multi-session work, follow the standard handoff protocol (`@~/dotfiles/instructions/handoff.instructions.md`) to persist the issue list and dependency order. Include @-references to the parent PRD issue.
