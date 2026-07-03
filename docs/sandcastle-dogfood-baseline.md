# Sandcastle Dogfood Baseline

Operational baseline for the Sandcastle dogfood test system — which workflows are covered, how they're tested, and when to investigate.

> **Automation entry point:** `.github/workflows/nightly-smoke.yml`
> **Report source:** `bin/smoke-sandcastle-report.sh`

---

## How It Works

The nightly smoke workflow runs daily at 06:00 UTC and on `workflow_dispatch`. It queries the last N runs of every Sandcastle workflow, aggregates pass/fail/skip status, and publishes a report artifact (`report.json` + `report.md`) to the GitHub Actions run.

### Running Manually

```bash
# Trigger via workflow_dispatch (default: last 5 runs per workflow)
gh workflow run nightly-smoke.yml

# With custom limit
gh workflow run nightly-smoke.yml -f limit=10

# Check the latest run
gh run list --workflow nightly-smoke.yml --limit 1
```

### Where Artifacts Are Published

Each run uploads a `smoke-report-N` artifact containing:

- **report.json** — machine-readable results with `summary.pass`, `summary.fail`, `summary.skip` counts and per-workflow entries including `name`, `latest_url`, and `latest_conclusion`
- **report.md** — human-readable markdown surfaced in the GitHub Actions step summary

Artifacts are retained for 30 days.

---

## Workflow Coverage

All 16 Sandcastle-related workflows tracked by the smoke harness:

| # | Workflow | Type |
|---|----------|------|
| 1 | Agent: Architecture Review | Agent workflow |
| 2 | Agent: Check Stale PRs | Agent workflow |
| 3 | Agent: Fix PR Feedback | Agent workflow |
| 4 | Agent: Implement Issue | Agent workflow |
| 5 | Agent: Implement PRD | Agent workflow |
| 6 | Agent: Merge PR | Agent workflow |
| 7 | Agent: Plan Issue | Agent workflow |
| 8 | Agent: Promote Queued | Agent workflow |
| 9 | Agent: Review Issue | Agent workflow |
| 10 | Agent: Update Branch | Agent workflow |
| 11 | Bridge Tests | CI |
| 12 | Copilot | CI |
| 13 | Integrity | CI |
| 14 | PR: request Copilot review | Automation |
| 15 | Proxy Canary | Monitoring |
| 16 | Sandcastle CI | CI |

Source: `SANDCASTLE_WORKFLOWS` array in `bin/smoke-sandcastle-report.sh`.

## Smoke Scripts

5 scripts that validate specific workflow coverage areas:

| Script | Coverage Area |
|--------|---------------|
| `bin/smoke-sandcastle-dispatch.sh` | Workflow dispatch triggers |
| `bin/smoke-sandcastle-issue-labels.sh` | Issue label automations |
| `bin/smoke-sandcastle-pr-path.sh` | PR-triggered workflow paths |
| `bin/smoke-sandcastle-promote-queued.sh` | Queue promotion workflow |
| `bin/smoke-sandcastle-scheduled.sh` | Scheduled workflow execution |

Source: `SMOKE_SCRIPTS` array in `bin/smoke-sandcastle-report.sh`.

---

## Regression Policy

**Any new red = P1 investigation.**

A workflow that was previously passing and now fails requires immediate investigation. The nightly report surfaces failures as GitHub Actions warnings — monitor the step summary for changes.

Acceptable failure modes:
- A workflow that has never run (skip) — expected for newly added workflows
- A workflow with a known, tracked issue — document in the report comment

Unacceptable:
- A previously-green workflow turning red with no associated PR or known cause
- Silent failures (workflow runs but produces no output or wrong output)

---

## Verification Run

<!-- Fill in after running the verification dispatch (issue #219) -->

| Field | Value |
|-------|-------|
| Verification run URL | _pending_ |
| Run date | _pending_ |
| Pass count | _pending_ |
| Fail count | _pending_ |
| Skip count | _pending_ |
| Coverage | _pending_ |

---

## References

- [PRD: Full Sandcastle workflow dogfood test system](https://github.com/arndvs/dotfiles-private/issues/33)
- [Slice 10: QA certification](https://github.com/arndvs/dotfiles-private/issues/43)
- `.github/workflows/nightly-smoke.yml` — automation entry point
- `bin/smoke-sandcastle-report.sh` — report generator
