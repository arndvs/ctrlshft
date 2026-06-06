# Triage Labels

Labels that drive the Sandcastle state machine. Applied to issues and PRs to trigger agent workflows via GitHub Actions.

## Trigger Labels (Issues)

These labels fire a GitHub Actions workflow when applied to an issue.

| Label | Trigger | Workflow | What happens |
|-------|---------|----------|-------------|
| `agent:implement` | `issues.labeled` | `agent-implement-issue.yml` | Agent checks out the default branch, reads the issue, creates a feature branch, implements the task, commits, and opens a PR. |
| `agent:implement-prd` | `issues.labeled` | `agent-implement-prd.yml` | Agent reads a PRD issue and its sub-issues, then implements all slices end-to-end (branching, coding, committing, PRs). |
| `agent:plan` | `issues.labeled` | `agent-plan-issue.yml` | Agent reads a PRD issue and decomposes it into sub-issues with acceptance criteria, types, and dependency order. |
| `agent:review` | `issues.labeled` | `agent-review-issue.yml` | Agent reviews the issue for clarity, feasibility, missing acceptance criteria, and posts a comment with findings. |
| `agent:architecture-review` | `issues.labeled` | `agent-architecture-review.yml` | Agent performs a scoped architecture review of the codebase relative to the issue, posting findings as a comment. |

## Trigger Labels (Pull Requests)

These labels fire a GitHub Actions workflow when applied to a PR.

| Label | Trigger | Workflow | What happens |
|-------|---------|----------|-------------|
| `agent:auto-fix` | `pull_request_review.submitted` | `agent-fix-pr-feedback.yml` | When a review is submitted (with `changes_requested` or a comment on a labeled PR), the agent reads review threads, scores them, applies fixes, and resolves threads. |
| `agent:merge` | `pull_request.labeled` | `agent-merge-pr.yml` | Agent squash-merges the PR with auto-merge enabled and deletes the source branch. |
| `agent:update-branch` | `pull_request.labeled` | `agent-update-branch.yml` | Agent rebases or merges the base branch into the PR branch to resolve conflicts or pick up upstream changes. |

## State Labels

These labels track issue/PR status. They are not triggers for workflows but communicate state to humans and scheduled workflows.

| Label | Applied to | Meaning |
|-------|-----------|---------|
| `queued` | Issues | Issue is ready for the next scheduled parallel agent sweep. The `agent-promote-queued.yml` workflow runs on a cron schedule (every 4 hours) and picks up `queued` issues for batch implementation. |
| `in-progress` | Issues | An agent is actively working on this issue. Set at the start of implementation, cleared on completion or failure. |
| `review-cap-reached` | PRs | The PR hit the maximum review round cap (default: 3 rounds). No further automatic fixes will be attempted. Requires human review. |
| `blocked` | Issues | The agent could not complete the task and requires human intervention. Usually accompanied by a comment explaining the blocker. |

## Classification Labels

These labels categorize issues for task selection and triage. They are informational and do not trigger workflows.

| Label | Meaning |
|-------|---------|
| `afk` | Can be implemented autonomously without human interaction. Safe for the AFK loop. |
| `hitl` | Requires human judgment (architectural decisions, design review, manual QA). Not suitable for autonomous execution. |

## Scheduled Workflows

Two workflows run on cron schedules rather than label triggers:

| Workflow | Schedule | What it does |
|----------|----------|-------------|
| `agent-promote-queued.yml` | Every 4 hours (`0 */4 * * *`) | Finds issues labeled `queued`, runs the parallel workflow to implement them in batch. |
| `agent-check-stale-prs.yml` | Weekdays at 9 AM UTC (`0 9 * * 1-5`) | Finds PRs with no activity for 7+ days and posts a reminder comment. |

## State Transitions

```
Issue created
  |
  v
[agent:review] -----> Agent posts clarity feedback
  |
  v
[agent:plan] -------> Agent decomposes into sub-issues
  |
  v
[queued] -----------> Awaits next scheduled sweep
  |                   (or apply agent:implement directly)
  v
[agent:implement] --> [in-progress] --> PR opened
                                         |
                                         v
                                    Code review posted
                                         |
                                         v
                              [agent:auto-fix] --> Fixes applied
                                         |         (up to round cap)
                                         v
                              [agent:merge] ----> Squash-merged
                                         |
                                         v
                              [review-cap-reached] --> Human review needed
```

When the agent cannot complete a task, it applies `blocked` and posts a comment explaining why.
