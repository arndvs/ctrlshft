# MCRDSE Repo Hygiene — Nightly Backlog Loop

Audit the six MCRDSE repos, build a stack-aware `repo-hygiene` skill, and wire a
nightly GitHub workflow that creates one well-scoped backlog issue per repo per
night to migrate the codebases toward clean structure.

## Pickup command

```
@working/active/mcrdse-repo-hygiene.md — pick up on remaining slices. Start with Slice 1.
```

## Key references

- `skills/repo-hygiene/` — the stack-aware skill (SKILL.md + references + scripts + assets)
- `working/refs/mcrdse-audit/audit.md` — the severity assessment of all six repos
- `working/refs/astro-files/` — the original Astro-only draft this generalizes
- `shft/engine/workflows/architecture-review.ts` — closest analog (scheduled, issue-creating, extraction-based)
- `shft/engine/workflows/keep-tests-tight.ts` — closest analog for the open-issue guard
- `shft/engine/lib/dispatch.ts` — workflow registry (repo-hygiene registered)
- `shft/engine/lib/prompt-contracts.test.ts` — prompt arg contract (updated)
- `test/sandcastle-smoke-coverage.sh` — workflow count guards (updated)
- `bin/smoke-sandcastle-report.sh` — `SANDCASTLE_WORKFLOWS` registry (updated)
- `shft/templates/labels.json` + `shft/docs/triage-labels.md` + `instructions/sandcastle-pipeline.instructions.md` — label definitions (updated)
- `shft/README.md`, `shft/docs/platform-spec.md`, `shft/docs/full-smoke-matrix.md`, `docs/sandcastle-dogfood-baseline.md` — docs (updated)

---

## 1. Context

The MCRDSE portfolio is six repos across four stacks, all with monolithic files
and near-zero layout/component reuse. The two flagship Astro sites have pages of
1,000–2,900 lines each. A nightly backlog loop is justified, but it must be
**stack-aware** — a single Astro-only skill covers only half the portfolio.

The `working/refs/astro-files/` draft is a solid single-repo, single-stack
implementation. This work generalizes it into a `repo-hygiene` skill that
dispatches by stack, and wires a nightly workflow per repo.

## 2. Design Decisions

| Decision | Choice |
| -------- | ------ |
| Skill name | `repo-hygiene` (generalizes the Astro-only `astro-refactor-pilot`) |
| Stack detection | `audit.mjs` detects `astro` / `static-html` / `worker-ts` / `python` / `generic` |
| Phase models | One per stack: `phases-astro.md`, `phases-static-html.md`, `phases-worker-ts.md`, `phases-python.md`, `phases-generic.md` |
| Workflow name | `repo-hygiene` (engine runner), `agent-repo-hygiene.yml` (workflow) |
| Trigger | `schedule` (daily, 02:30 UTC) + `workflow_dispatch` with `dry_run` input |
| Open-issue guard | Engine runner checks `gh issue list --label repo-hygiene --state open`; skips agent if one is open |
| Issue creation | Workflow creates the issue + applies `repo-hygiene` and `phase-<n>` labels |
| Structured output | Two-phase `runWithExtraction` (produce drafts; extraction reports) |
| Output contract | `{ status: "proposed" \| "skipped", title, body, phase, stack, oneLineSummary, candidatesConsidered }` |
| Labels | New `repo-hygiene` + `phase-0` … `phase-5` (state markers, no transitions) |
| Concurrency | `group: agent-repo-hygiene`, `cancel-in-progress: false` |
| Permissions | `contents: write`, `issues: write` (no PR writes — a human or separate agent executes) |
| Proxy | Standard `proxy_preflight.sh` gate; `{{DEFAULT_BRANCH}}` substitution |
| Vendoring | New files under `shft/engine/`, `shft/templates/`; auto-copied by init/update |
| Docs | Updated `shft/README.md`, `platform-spec.md`, `full-smoke-matrix.md`, `triage-labels.md`, `labels.json`, `sandcastle-dogfood-baseline.md`, `skills/README.md` |

## 3. Vertical Slices

### ✅ Slice 1 — Audit report
Type: AFK · Size: S
Steps:
1. Survey all six repos (stack, file counts, line counts, largest files, layout/component adoption).
2. Write `working/refs/mcrdse-audit/audit.md` with per-repo severity and remediation priority.
Acceptance: report quantifies the problem and ranks repos.

### ✅ Slice 2 — `repo-hygiene` skill
Type: AFK · Size: M
Steps:
1. Create `skills/repo-hygiene/SKILL.md` (stack-aware, audit/issue modes, open-issue guard, phase gating).
2. Create `scripts/audit.mjs` (stack detection + per-stack signals).
3. Create `references/phases-<stack>.md` for all five stacks.
4. Create `references/recipes.md`, `references/metrics.md`, `references/issue-template.md`, `references/setup.md`.
5. Create `assets/state.example.json`, `assets/nightly-refactor.yml`.
Acceptance: `bin/validate-skills.sh` passes; `audit.mjs` runs correctly on all four real stacks.

### ✅ Slice 3 — Engine runner + workflow
Type: AFK · Size: M
Steps:
1. Create `shft/engine/schemas/repo-hygiene-output.ts` (Zod discriminated union).
2. Create `shft/engine/workflows/repo-hygiene.ts` (`runRepoHygiene` with open-issue guard + `runWithExtraction`).
3. Register `repo-hygiene` in `shft/engine/lib/dispatch.ts`.
4. Create `shft/templates/prompts/repo-hygiene.md` + `shft/templates/extractions/repo-hygiene.md`.
5. Create `shft/templates/workflows/agent-repo-hygiene.yml`.
6. Update `prompt-contracts.test.ts`, `dispatch.test.ts`, `sandcastle-smoke-coverage.sh`, `smoke-sandcastle-report.sh`.
7. Add `repo-hygiene` + `phase-*` labels to `pipeline-states.ts`, `labels.json`, `triage-labels.md`, `sandcastle-pipeline.instructions.md`; regenerate `pipeline-label-data.sh`.
Acceptance: `pnpm test` (322 tests) and `pnpm typecheck` pass.

### ⬜ Slice 4 — Docs
Type: AFK · Size: S
Steps:
1. Update `shft/README.md`, `shft/docs/platform-spec.md`, `shft/docs/full-smoke-matrix.md`, `docs/sandcastle-dogfood-baseline.md`, `skills/README.md`.
Acceptance: all references to the workflow inventory include `agent-repo-hygiene.yml`.

### ⬜ Slice 5 — Install into MCRDSE repos
Type: HITL · Size: M · Blocked by: Slice 3
Steps:
1. For each of the six repos, run `ctrl init-sandcastle` (or copy the vendored files) to install `.refactor/` + `agent-repo-hygiene.yml`.
2. Add `ANTHROPIC_API_KEY` (or proxy secrets) as repo secrets.
3. Create the `repo-hygiene` + `phase-*` labels.
4. Run the workflow manually once with `dry_run: true` before letting the schedule take over.
Acceptance: each repo has the loop installed and a dry-run issue drafted.

## 4. Known gotchas (from setup.md)

- **Scheduled workflows are disabled after 60 days of repo inactivity.** The nightly ledger commit counts as activity, which mostly handles it — but check monthly.
- **Cron times are UTC and approximate.** The loop is idempotent by design.
- **`GITHUB_TOKEN`-created issues don't trigger other workflows.** If a downstream agent should auto-execute the issue, use a PAT/GitHub App token.
- **Ledger commits and branch protection.** If `main` is protected, exempt the bot or drop the commit step.
- **Run in dry-run for the first week.** Watch task size — if PRs land at 900 lines, tighten the budget in SKILL.md.
