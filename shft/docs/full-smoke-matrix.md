# Full Sandcastle Smoke Matrix

This is the canonical contract for dogfooding every installed `agent-*` GitHub Actions workflow. It defines what each smoke test must trigger, what setup it needs, what terminal state counts as success, and when a skipped run is acceptable.

Use this matrix as the source of truth for the full-smoke implementation slices in #33. The first implementation can be manual or semi-automated, but every run must produce evidence that maps back to these rows.

## Contract

A smoke run is complete only when every workflow row records one of these result values:

| Result | Meaning | Required evidence |
|--------|---------|-------------------|
| `pass` | The workflow ran on the intended trigger and reached its expected terminal state. | Workflow run URL, target issue or PR URL, final labels/state, and any created PR/issue URL. |
| `expected-skip` | The workflow intentionally refused or skipped because the matrix's skip semantics matched the fixture. | Workflow run URL and the refusal/skip comment, summary, or log line. |
| `fail` | The workflow ran but did not reach the expected terminal state, or skipped for a reason not listed here. | Workflow run URL, failure reason, final labels/state, and the suspected owner slice. |

Rules:

- Use disposable test issues, PRs, and branches unless the row explicitly targets scheduled maintenance.
- Capture the GitHub Actions run URL for every row; local CLI output is supporting evidence, not a replacement.
- Validate labels after the run, not only logs. The label state machine is part of the product.
- Keep `AGENT_PAT` configured for chained label transitions. Rows that prove the missing-token failure path must use a separate fixture.
- Do not print secret values in reports or logs. Record only whether each required secret was configured.
- Treat fork PR refusal as a pass only for the explicit fork-safety fixture on `pull_request_target` workflows.

For the safe scheduled-workflow dispatch slice, use `ctrl smoke-sandcastle-dispatch`. It defaults to `agent-check-stale-prs.yml`, waits for completion, and prints the run URL, status, conclusion, and failed step names. Other `workflow_dispatch` workflows require `--allow-side-effects` so mutating fixtures are explicit.

For the issue-label state-machine slice, use `ctrl smoke-sandcastle-issue-labels`. It creates a disposable issue, applies `Sandcastle`, waits for `agent-review-issue.yml`, `agent-plan-issue.yml`, and `agent-implement-issue.yml`, verifies the terminal `agent:pr-open` label state, and closes disposable issue/PR artifacts. Live runs require `--allow-side-effects`; use `--dry-run` to preview without creating artifacts.

For exercising schedule-backed workflows on-demand, use `ctrl smoke-sandcastle-scheduled`. It discovers every workflow that declares both `schedule:` and `workflow_dispatch` (currently `agent-architecture-review.yml` and `agent-check-stale-prs.yml`), dispatches each as a schedule-equivalent run via `smoke-sandcastle-dispatch` with a standardized timeout and retry policy, and aggregates pass/fail across all of them. Use `--list` to enumerate the discovered workflows, `--dry-run` to preview the planned dispatches, and `--allow-side-effects` for live runs (which may create issues, e.g. a `source:architecture-review` issue).

For the queued-promotion dependency-unblocking slice, use `ctrl smoke-sandcastle-promote-queued`. It creates disposable blocker/dependent issue pairs, links them with the native GitHub "blocked by" dependency, labels each dependent `agent:queued`, and closes the blocker to trigger `agent-promote-queued.yml`. It verifies the promotion run succeeded and the dependent lost `agent:queued` and gained `agent:implement`, repeating across at least two disposable pairs (`--pairs`, default 2), then cleans up the issues plus any branch/PR a cascading `agent-implement-issue.yml` raised. Requires `AGENT_PAT`; live runs require `--allow-side-effects`, and `--dry-run` previews without creating artifacts.

For the PR-path state-machine slice, use `ctrl smoke-sandcastle-pr-path`. It opens a disposable same-repository PR (created hermetically through the GitHub API, so the local pre-commit hook never runs), then labels it `agent:update-branch` and `agent:fix` in turn — proving each automation green when its `pull_request_target` workflow run completes with conclusion `success` — before cleaning up the PR and branch. The `agent:merge` path is destructive and runs only with explicit `--confirm-merge`. The update-branch and fix-pr-feedback workflows execute agent code, so live runs require the hosted Copilot proxy to be reachable from Actions; `--dry-run` previews without creating artifacts and `--allow-side-effects` is required for live runs.

## Global setup

| Requirement | Purpose |
|-------------|---------|
| Initialized Sandcastle repo | Provides `.github/workflows/agent-*.yml`, `.sandcastle/run.ts`, vendored engine, prompts, scripts, and `sandcastle.config.json`. |
| Default branch configured | Workflows check out the stamped default branch value resolved from `{{DEFAULT_BRANCH}}`. Dotfiles dogfood uses `dev`. |
| Labels installed | Required labels include `Sandcastle`, `agent:review`, `agent:implement`, `agent:implement-prd`, `agent:fix`, `agent:update-branch`, `agent:merge`, `agent:queued`, `agent:blocked`, `agent:in-progress`, `agent:pr-open`, `source:architecture-review`, `repo-hygiene`, and `phase-0` … `phase-5`. |
| Secrets configured | `LITELLM_BASE_URL`, `LITELLM_MASTER_KEY`, and `AGENT_PAT`. `GITHUB_TOKEN` is provided by Actions. |
| Package manager available | Workflows enable Corepack and install `.sandcastle/engine` dependencies with the configured package manager. |
| GitHub CLI available | Workflow steps use `gh` for issue, PR, label, and GraphQL operations. |

## Workflow matrix

| Workflow | Trigger source | Fixture setup | Expected terminal state | Secrets / permissions | Skip semantics |
|----------|----------------|---------------|-------------------------|--------------------------------|----------------|
| `agent-review-issue.yml` | `issues:labeled` with `Sandcastle` | Open a disposable issue with enough context for either direct implementation or planning; apply `Sandcastle`. | `Sandcastle` removed, `agent:in-progress` removed, `agent:review` added. On failure, `agent:blocked` is added with a workflow-run comment. | Secrets: `LITELLM_BASE_URL`, `LITELLM_MASTER_KEY`, `AGENT_PAT` for the `agent:review` handoff. Permissions: `contents: read`, `issues: write`. | Missing `AGENT_PAT` is an expected failure fixture only when testing token hardening; otherwise it is a fail. |
| `agent-plan-issue.yml` | `issues:labeled` with `agent:review` | Use an issue that should become implementation work; apply `agent:review`. | `agent:review` removed, `agent:in-progress` removed, `agent:implement` added. On failure, `agent:blocked` is added with a workflow-run comment. | Secrets: `LITELLM_BASE_URL`, `LITELLM_MASTER_KEY`, `AGENT_PAT` for the `agent:implement` handoff. Permissions: `contents: read`, `issues: write`. | Missing `AGENT_PAT` is an expected failure fixture only when testing token hardening; otherwise it is a fail. |
| `agent-implement-issue.yml` | `issues:labeled` with `agent:implement` | Open a small disposable issue whose expected code/doc change is safe; apply `agent:implement`. | Branch `agent/issue-<number>-<slug>` pushed, draft PR opened or reused, `agent:pr-open` added to the issue, `agent:in-progress` removed. On failure, `agent:blocked` is added with a workflow-run comment. | Secrets: `LITELLM_BASE_URL`, `LITELLM_MASTER_KEY`, `AGENT_PAT` for branch, PR, and label operations. Permissions: `contents: write`, `issues: write`, `pull-requests: write`. | Existing open PR for the computed branch is acceptable; the workflow should not create a duplicate PR. |
| `agent-implement-prd.yml` | `issues:labeled` with `agent:implement-prd` | Create a parent PRD issue with flat sub-issues; at least one sub-issue is open. Apply `agent:implement-prd` to the parent. | One open sub-issue is implemented and closed. The PRD branch is pushed and a draft PR is opened or reused. If more sub-issues remain, `agent:implement-prd` is re-added to the parent; otherwise the PR is marked ready, which triggers `pr-auto-copilot-review.yml` through `ready_for_review`. `agent:in-progress` is removed from the PRD. | Secrets: `LITELLM_BASE_URL`, `LITELLM_MASTER_KEY`, `AGENT_PAT` for self-chaining and ready-for-review handoff. Permissions: `contents: write`, `pull-requests: write`, `issues: write`. | Parent with no sub-issues exits silently. Nested PRD, child issue with sub-issues, or all sub-issues closed are expected refusal fixtures that remove `agent:implement-prd`, add `agent:blocked`, and comment with the reason. |
| `agent-fix-pr-feedback.yml` | `pull_request_target:labeled` with `agent:fix` | Use a same-repository PR with actionable review comments or a controlled fixture comment; apply `agent:fix`. | `agent:fix` removed, fix commits pushed to the PR branch when needed, `agent:in-progress` removed. On failure, `agent:blocked` is added to the PR with a workflow-run comment. | Secrets: `LITELLM_BASE_URL`, `LITELLM_MASTER_KEY`, `AGENT_PAT` for label and branch operations. Permissions: `contents: write`, `pull-requests: write`, `issues: write`. | Fork PRs must be refused: `agent:fix` removed, `agent:blocked` added, and a safety comment posted. That refusal is a pass for the fork-safety fixture only. |
| `agent-update-branch.yml` | `pull_request_target:labeled` with `agent:update-branch` | Use a same-repository PR branch behind the base branch or with a controlled no-op update case; apply `agent:update-branch`. | `agent:update-branch` removed, branch updated when `should_push.txt` is `true`, optional PR comment posted, `agent:in-progress` removed. On non-fast-forward or other failure, `agent:blocked` is added with a workflow-run comment. | Secrets: `LITELLM_BASE_URL`, `LITELLM_MASTER_KEY`, `AGENT_PAT` for label and branch operations. Permissions: `contents: write`, `pull-requests: write`, `issues: write`. | No-op update where `should_push.txt` is absent or not `true` is a pass if the workflow reports `Nothing to push.` Fork PRs must be refused and are a pass only for the fork-safety fixture. |
| `agent-merge-pr.yml` | `pull_request_target:labeled` with `agent:merge` | Use a same-repository PR that has passed required checks and review policy; apply `agent:merge`. | `agent:merge` removed, merge runner completes, PR is merged by the runner, and `agent:in-progress` is removed. On failure, `agent:blocked` is added with a workflow-run comment. | Secrets: `LITELLM_BASE_URL`, `LITELLM_MASTER_KEY`, `AGENT_PAT` for label and merge operations. Permissions: `contents: write`, `pull-requests: write`, `issues: write`. | Fork PRs must be refused and are a pass only for the fork-safety fixture. PRs that fail merge policy should become `agent:blocked`, not silently pass. |
| `agent-architecture-review.yml` | `schedule` or `workflow_dispatch` | Dispatch manually for deterministic smoke; ensure default branch checkout and engine install are clean. | Workflow summary is written. If output status is `proposed`, a `source:architecture-review` issue is created. If output status is `skipped`, no issue is created and the summary explains the skip reason. | Secrets: `LITELLM_BASE_URL`, `LITELLM_MASTER_KEY`; `AGENT_PAT` or `GITHUB_TOKEN` for issue creation. Permissions: `contents: read`, `issues: write`. | `skipped` output is a pass when the summary says no fresh candidates were found. Missing output file is a fail unless the run is specifically testing crash reporting. |
| `agent-check-stale-prs.yml` | `schedule` or `workflow_dispatch` | Dispatch manually with at least one open PR fixture when possible; otherwise run against the current repo state. | Runner completes and reports stale PR findings or no stale PRs without mutating unrelated PRs. | Secrets: `LITELLM_BASE_URL`, `LITELLM_MASTER_KEY`; `AGENT_PAT` or `GITHUB_TOKEN` for PR/issue operations. Permissions: `contents: read`, `pull-requests: write`, `issues: write`. | No stale PRs is a pass if the run completes cleanly and reports an empty finding set. |
| `agent-keep-tests-tight.yml` | `schedule` or `workflow_dispatch` | Dispatch manually on a branch with recent commits (within 24h) to exercise the trim path; dispatch on a branch with no commits in 24h to exercise the early-exit path. | If output status is `changed`, the branch is pushed and a draft PR is opened (or reused). If output status is `no-changes`, no branch is pushed and no PR is opened; the summary explains the skip reason. | Secrets: `LITELLM_BASE_URL`, `LITELLM_MASTER_KEY`; `AGENT_PAT` or `GITHUB_TOKEN` for branch/PR operations. Permissions: `contents: write`, `pull-requests: write`. | `no-changes` output is a pass when the summary says no commits in the last 24 hours. Missing output file is a fail unless the run is specifically testing crash reporting. |
| `agent-repo-hygiene.yml` | `schedule` or `workflow_dispatch` | Dispatch manually with no open `repo-hygiene` issue to exercise the propose path; dispatch with an open `repo-hygiene` issue to exercise the open-issue guard. | If output status is `proposed`, a `repo-hygiene` + `phase-<n>` issue is created. If output status is `skipped`, no issue is created and the summary explains the skip reason. | Secrets: `LITELLM_BASE_URL`, `LITELLM_MASTER_KEY`; `AGENT_PAT` or `GITHUB_TOKEN` for issue creation. Permissions: `contents: write`, `issues: write`. | `skipped` output is a pass when the summary says a task is already open or the repo is clean. Missing output file is a fail unless the run is specifically testing crash reporting. |
| `agent-promote-queued.yml` | `issues:closed` where `state_reason != not_planned` | Create an open issue with `agent:queued` that is blocked by another issue. Close the blocker as completed. | If no open blockers remain, dependent issue loses `agent:queued`, receives a promotion comment, and gains `agent:implement` through `AGENT_PAT`. If promotion fails, dependent issue gains `agent:blocked` with a token failure comment. | Secrets: `AGENT_PAT` for adding `agent:implement`; `GITHUB_TOKEN` can read dependency state and remove labels. Permissions: `issues: write`. | Closing a blocker as `not_planned` must not promote anything. Dependents that are not `agent:queued`, are `agent:in-progress`, still have open blockers, lost `agent:queued`, or are sub-issues are expected skips/refusals with the documented logs/comments. |

## Report shape

Each full-smoke report must include one row per workflow:

| Field | Description |
|-------|-------------|
| Workflow | File name from `shft/templates/workflows/`. |
| Fixture | Issue, PR, branch, or manual dispatch used for the run. |
| Trigger | Label, close event, schedule, or `workflow_dispatch` event. |
| Run URL | GitHub Actions run URL. |
| Result | `pass`, `expected-skip`, or `fail`. |
| Evidence | Final labels/state plus created issue/PR URLs or summary output. |
| Notes | Short explanation for any skip or failure. |

The report is valid only if it covers all 10 workflow files currently installed by `ctrl init-sandcastle`.
