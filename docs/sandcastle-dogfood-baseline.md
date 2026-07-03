# Dogfood Test Coverage Baseline

Baseline recorded for Sandcastle QA certification (issue #43, Slice 10).

## Overview

This document records the dogfood test coverage state for all Sandcastle
workflows installed in this repository. It serves as the reference for
regression detection and coverage gap analysis.

- **Workflows tracked:** 16 (10 agent + 6 infrastructure)
- **Smoke scripts:** 6 (5 active exercisers + 1 report aggregator)
- **Harness tests:** 6 (unit tests for each smoke script)
- **Nightly cron:** `nightly-smoke.yml` runs daily at 06:00 UTC

## Workflow Coverage Matrix

Each workflow is categorized by its coverage type:

- **Active:** A smoke script directly triggers and verifies the workflow.
- **Passive:** The report aggregator queries run history without triggering.
- **Infrastructure:** CI/CD workflows exercised by normal development flow.

### Agent Workflows (10)

| Workflow | File | Coverage | Smoke Script |
|----------|------|----------|--------------|
| Architecture Review | `agent-architecture-review.yml` | Active | `smoke-sandcastle-scheduled.sh` |
| Check Stale PRs | `agent-check-stale-prs.yml` | Active | `smoke-sandcastle-dispatch.sh` |
| Fix PR Feedback | `agent-fix-pr-feedback.yml` | Active | `smoke-sandcastle-pr-path.sh` |
| Implement Issue | `agent-implement-issue.yml` | Active | `smoke-sandcastle-issue-labels.sh`, `smoke-sandcastle-promote-queued.sh` |
| Implement PRD | `agent-implement-prd.yml` | Passive | `smoke-sandcastle-report.sh` (query only) |
| Merge PR | `agent-merge-pr.yml` | Active | `smoke-sandcastle-pr-path.sh` |
| Plan Issue | `agent-plan-issue.yml` | Active | `smoke-sandcastle-issue-labels.sh` |
| Promote Queued | `agent-promote-queued.yml` | Active | `smoke-sandcastle-promote-queued.sh` |
| Review Issue | `agent-review-issue.yml` | Active | `smoke-sandcastle-issue-labels.sh` |
| Update Branch | `agent-update-branch.yml` | Active | `smoke-sandcastle-pr-path.sh` |

### Infrastructure Workflows (6)

| Workflow | File | Coverage | Notes |
|----------|------|----------|-------|
| Bridge Tests | `bridge-tests.yml` | Passive | Triggered by PR activity; queried by report aggregator |
| Copilot | `copilot.yml` | Passive | Triggered by PR labeling; queried by report aggregator |
| Integrity | `integrity.yml` | Passive | Triggered by push to dev; queried by report aggregator |
| PR: request Copilot review | `pr-auto-copilot-review.yml` | Passive | Triggered by PR open/ready; queried by report aggregator |
| Proxy Canary | `proxy-canary.yml` | Passive | Scheduled canary; queried by report aggregator |
| Sandcastle CI | `sandcastle-ci.yml` | Passive | Triggered by push/PR; queried by report aggregator |

## Smoke Scripts

| Script | Purpose | Harness Test |
|--------|---------|--------------|
| `bin/smoke-sandcastle-dispatch.sh` | Safe workflow_dispatch trigger + wait | `test/sandcastle-dispatch-smoke.sh` |
| `bin/smoke-sandcastle-issue-labels.sh` | Issue-label state machine (review -> plan -> implement) | `test/sandcastle-issue-label-smoke.sh` |
| `bin/smoke-sandcastle-pr-path.sh` | PR-path state machine (update-branch, fix, merge) | `test/sandcastle-pr-path-smoke.sh` |
| `bin/smoke-sandcastle-promote-queued.sh` | Dependency-unblocking promotion flow | `test/sandcastle-promote-queued-smoke.sh` |
| `bin/smoke-sandcastle-scheduled.sh` | Schedule-equivalent dispatch for cron workflows | `test/sandcastle-scheduled-smoke.sh` |
| `bin/smoke-sandcastle-report.sh` | Aggregate report across all 16 workflows | `test/sandcastle-report-smoke.sh` |

## Coverage Verification

The structural QA gate (`test/sandcastle-smoke-coverage.sh`) continuously verifies:

1. Every installed agent workflow is listed in the report aggregator inventory.
2. Every agent workflow maps to at least one smoke script or report path.
3. The full smoke matrix doc (`shft/docs/full-smoke-matrix.md`) references every workflow.
4. The nightly cron workflow exists, has a schedule trigger, and runs the report aggregator.
5. Every smoke script has a corresponding harness test.
6. This baseline document exists.

## Known Gaps

- **`agent-implement-prd.yml`** has passive coverage only. No active smoke script
  creates a PRD fixture and exercises the sub-issue iteration loop. This is
  acceptable for the initial baseline because PRD implementation is a complex
  multi-issue workflow that requires careful fixture management. A dedicated
  smoke script is tracked for future work.

- **Infrastructure workflows** (Bridge Tests, Copilot, Integrity, Proxy Canary,
  Sandcastle CI, PR: request Copilot review) are covered passively through the
  report aggregator's run-history queries. They are exercised organically by
  normal development flow (push, PR, schedule) and do not need dedicated smoke
  fixtures.

## Nightly Regression Detection

The `nightly-smoke.yml` workflow runs at 06:00 UTC daily and:

1. Executes `bin/smoke-sandcastle-report.sh` against live run data.
2. Produces JSON + markdown report artifacts (30-day retention).
3. Emits `::warning::` annotations when any workflow has recent failures.
4. Publishes the markdown report to the GitHub Actions step summary.

## Reference

- Full smoke matrix contract: `shft/docs/full-smoke-matrix.md`
- Report aggregator: `bin/smoke-sandcastle-report.sh`
- Nightly workflow: `.github/workflows/nightly-smoke.yml`
- QA certification issue: #43
