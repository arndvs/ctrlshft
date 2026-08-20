# ctrlshft-public — SaaS Starter Lift Plan (bidirectional)

> **Status:** Implemented (2026-08-16) — see `feat/lift-saas-starter-patterns`
> **Date:** 2026-08-15 (updated 2026-08-16)
> **Source:** `cmd-private/raw/uploads/saas-starter/` (SvelteKit + Convex + Better Auth template)
> **Target:** `ctrlshft-public` (Node HUD daemon + bash tooling + sandcastle pipeline)
> **Cross-ref:** `cmd-private/wiki/concepts/saas-starter-lift.md`

ctrlshft is the **reverse case**: it already *exceeds* the starter on agent-workflow, governance, and observability. The lift is bidirectional — pull the starter's false-green prevention in, push ctrlshft's governance patterns out.

## Pull INTO ctrlshft (from the starter) — IMPLEMENTED

| # | Pattern | Status | Where |
|---|---------|--------|-------|
| 1 | Ledger-accounted static-check gate | ✅ Done | `test/run-all.sh` — every green suite must emit assertion evidence |
| 2 | Regression-guard contract | ✅ Done | `shft/templates/workflows/require-regression-guard.yml` + PR template verdict line |
| 3 | Bot-attribution check | ✅ Pre-existing | `shft/templates/workflows/check-attribution.yml` |
| 4 | Skills provenance lockfile | ✅ Done | `skills/skills-lock.json` + `bin/generate-skills-lock.sh` + `bin/validate-skills-lock.sh` |
| 5 | Worktree safety model | ✅ Done | `bin/ctrl-worktree.sh` (create/prune) + `test/worktree-safety.sh` |
| 6 | SHA-pinned workflow actions | ✅ Done | Every `checkout@v4` / `setup-node@v4` → immutable SHA + `# vX.Y.Z` |
| 7 | Executable doc policy (ADR) | ✅ Done | `docs/adr/ADR-007-executable-doc-policy.md` |

### 1. Ledger-accounted static-check gate
- **Why:** ctrlshft's `test/run-all.sh` is thorough but doesn't prove each suite did real work before reporting green.
- **Source:** `saas-starter/scripts/static-checks.ts` (`assertWorkPerformed` invariant).
- **Acceptance:** a run that names suites but checks nothing fails.

### 2. Regression-guard contract
- **Why:** no enforcement that fix PRs state their guard.
- **Source:** `saas-starter/.github/workflows/require-regression-guard.yml`.
- **Acceptance:** every fix PR states `Regression guard:` verdict.

### 3. Bot-attribution check
- **Why:** keeps AI Co-Authored-By trailers out of the default branch.
- **Source:** `saas-starter/.github/workflows/check-attribution.yml`.
- **Acceptance:** bot trailers blocked from default branch.

## Push OUT of ctrlshft (to the starter + other repos)

These are ctrlshft patterns the starter and other repos should adopt. Document them in `cmd-private/wiki/concepts/saas-starter-lift.md` (already done for the crown jewels).

1. **Config-drift-as-a-test** (`test/config-consistency.sh`) — converts "this should always be true but nothing checks it" into a red blocking check.
2. **Fail-mode discipline for hooks** — every hook declares `FAIL_MODE: closed|open`; irreversible-damage hooks fail closed, quality hooks fail open.
3. **Three-tier credential isolation** (`.env.agent` vs `.env.secrets` vs AFK tokens) — process-scoped secrets agents can't access.
4. **Four-tier progressive disclosure** for instructions — keeps the always-on payload small.
5. **Defense-in-depth branch protection** — git pre-push hook + regression test + server-side ruleset.

## Propagation path

Producer → private → consumer: `ctrlshft-public/shft/templates/` (authoritative) flows to
`dotfiles-private` via `update-sandcastle.sh` (`SANDBOX_PRODUCER` default), and to consumer repos
via `init-sandcastle` / `update-sandcastle`. The `require-*.yml` stale-workflow glob extension was
synced to both sides; `update-sandcastle --dry-run` on dotfiles-private confirms the new
regression-guard template is detected for install.

## Source reference

| Direction | Pattern | Source |
|---|---|---|
| Pull | Ledger gate | `saas-starter/scripts/static-checks.ts` |
| Pull | Regression-guard contract | `saas-starter/.github/workflows/require-regression-guard.yml` |
| Pull | Bot-attribution check | `saas-starter/.github/workflows/check-attribution.yml` |
| Pull | Skills provenance lockfile | `saas-starter/skills-lock.json` |
| Pull | Worktree safety model | `saas-starter/scripts/prune-worktrees.ts` |
| Push | Config-drift-as-test | `ctrlshft-public/test/config-consistency.sh` |
| Push | Fail-mode discipline | `ctrlshft-public/hooks/` |
| Push | Three-tier secrets | `ctrlshft-public/.env.agent.example` + `.env.secrets.example` |
| Push | Progressive disclosure | `ctrlshft-public/instructions/` |