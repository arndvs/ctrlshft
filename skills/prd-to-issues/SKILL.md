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
   - **AFK** — can be implemented and merged without human interaction. Prefer AFK where possible.
   - **Human-in-the-loop (HITL)** — requires human interaction such as an architectural decision, design review, or taste judgment.

5. **Create a QA issue** — always create a final issue with a detailed manual QA plan for all items that require human verification. This is the last issue in the dependency chain.

6. **Quiz the user** — present the proposed breakdown and ask:
   - Does the granularity feel right?
   - Are the dependency relationships correct?
   - Should any slices be split further?
   - Are the correct slices marked as HITL vs AFK?

7. **Create GitHub issues** — generate issues using this template:

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

## Handoff

After issues are created, offer:

1. `/do-work` — start implementing the first slice
2. **Save plan to `working/`** — if context is high or multi-session work, follow the standard handoff protocol (global instructions `<handoff>`) to persist the issue list and dependency order. Include @-references to the parent PRD issue.
