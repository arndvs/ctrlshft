# Installing the loop

## Files

```
.refactor/
  audit.mjs          <- from scripts/
  state.json         <- from assets/state.example.json, emptied out
  routes.json        <- generated in Phase 0
  baseline/          <- HTML hashes from Phase 0
.github/workflows/
  nightly-refactor.yml
```

## Repo setup

1. Add `ANTHROPIC_API_KEY` as a repository secret.
2. Create the labels: `repo-hygiene`, and `phase-0` through `phase-5`.
3. Confirm Actions has write access to issues (Settings → Actions → General → Workflow permissions).
4. Run the workflow manually once with `dry_run: true` before letting the schedule take over.

## Known gotchas

**Scheduled workflows are disabled after 60 days of repo inactivity.** The whole point of this loop is steady progress on a repo that might otherwise be quiet, so this will bite eventually. The nightly ledger commit counts as activity, which mostly handles it — but if the loop goes idle because every task is blocked, the cron dies quietly. Check in monthly.

**Cron times are UTC and approximate.** Scheduled runs are queued at lowest priority and can be delayed 10–30 minutes, occasionally skipped entirely under load. Never schedule anything time-sensitive; the loop is designed to be idempotent precisely because runs get skipped.

**`GITHUB_TOKEN`-created issues don't trigger other workflows.** If you want a downstream automation to pick up the issue and execute it, you need a PAT or GitHub App token instead. This is intentional on GitHub's side to prevent recursive workflow triggers.

**Ledger commits and branch protection.** If `main` is protected, the ledger push will fail. Either exempt the bot, or drop the commit step and let the ledger live only in issue history — the audit is the important state anyway, and the ledger is recoverable from closed issues.

## First week

Run in dry-run mode for the first three or four nights and read the proposed issues without executing them. What you're checking:

- Is it staying in the right phase, or trying to jump to Tailwind?
- Are the file lists specific enough that you could hand the issue to a stranger?
- Are the tasks small enough that one PR closes them?

If tasks are consistently too big, tighten the size budget in `SKILL.md` before turning the loop loose. The failure mode you're guarding against isn't bad refactoring — it's a growing pile of half-finished 900-line PRs that nobody wants to review.

## Turning it off

When the final phase's exit criteria are met, delete the schedule block and keep `workflow_dispatch`. The audit stays useful as an on-demand health check long after the refactor is done.
