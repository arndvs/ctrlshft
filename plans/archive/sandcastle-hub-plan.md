# Sandcastle Hub — Implementation Plan
> **Archived** — implemented; see git history for the shipping commits. This plan is kept for reference only.

> **Status:** Proposed — awaiting approval
> **Date:** 2026-08-15
> **Derived from:** `docs/sandcastle-hub-architecture.md` + `docs/adr/ADR-008-ctrlshft-hub.md`
> **Executed by:** AFK agents (shft) for AFK slices; human for HITL slices

---

## 1. Context

Sandcastle's agent engine is currently vendored as ~101 files into each of 8 consumer repos, causing weekly drift, re-vendor churn, and nightly agents proposing edits to engine copies. We are replacing the vendoring model with a **public hub repo** (`arndvs/ctrlshft-hub`) that is the single source of truth: consumers keep only `sandcastle.config.json` + thin workflow stubs + a 1-file SHA-lock, and reference the hub's remote composite actions via `uses: arndvs/ctrlshft-hub/...@main`. This eliminates drift by construction, turns 8 parallel re-vendor PRs into a single hub release, and produces a public portfolio artifact. The engine's template-resolution and prompt-override code already supports this model (verified against `shft/engine/lib/default-template-paths.ts` and `resolve-prompt.ts`).

---

## 2. Design Decisions

| Decision | Choice |
| --- | --- |
| Hub repo | New public repo `arndvs/ctrlshft-hub` (`arndvs/sandcastle` is taken by a fork) |
| Consumer refs | `@main` + monthly SHA-lock review (per-user approval: "go with the recommended suggestions") |
| Action model | Composite actions; single `agent-run` action (setup+preflight+engine+publish+summary) |
| Workflow model | Reusable `workflow_call` jobs for lifecycle-heavy agents; inline stubs for simple scheduled agents |
| Consumer config | `sandcastle.config.json` stays in consumer repo (unchanged) |
| Prompt overrides | Consumer `promptDir` overrides hub templates by name (existing `resolvePrompt` contract) |
| Version pin | `.sandcastle/hub-version.json` = `{ ref, lastPinnedSha, reviewedAt }` |
| Drift workflow | `sandcastle-drift.yml` becomes SHA-drift check vs hub latest |
| Migration | Pilot `cmd-public` → baseline → observe → rollout 7 more |
| `update-sandcastle.sh` | Retired for consumers; replaced by hub `hub/release.sh` |
| cmd-private | Stays non-consumer (no sandcastle install) |
| ctrlshft-public `shft/engine` | Migrated into hub; ctrlshft-public delegates (docs, CI refs) |

---

## 3. Vertical Slices

> Each slice is independently shippable and wires end-to-end. AFK slices run fully autonomously; HITL slices need human judgment/access.

---

### ☐ S1: Create hub repo + seed skeleton
Type: AFK
Size: S
Blocked by: none
Steps:
1. `gh repo create arndvs/ctrlshft-hub --public --description "Single source of truth for the Sandcastle agent engine — composite actions, reusable workflows, templates, and the TypeScript engine."`
2. Clone to `~/dev/clients/ctrlshft-hub`.
3. Add `.gitignore` (node_modules, *.log, .env*), `LICENSE` (MIT), `README.md` placeholder, `CODEOWNERS` (maintainer).
4. Set default branch `main`; push initial commit.
Acceptance criteria: Public repo exists; `gh repo view arndvs/ctrlshft-hub` succeeds; README renders.
Feedback loops: `gh repo view`, `git status`.

---

### ☐ S2: Move engine into hub (with tests) — sibling layout REQUIRED
Type: AFK
Size: M
Blocked by: S1
Steps:
1. Copy `ctrlshft-public/shft/engine/` → `ctrlshft-hub/engine/` (lib/, workflows/, schemas/, run.ts, package.json, pnpm-lock.yaml, tsconfig.json, test/).
2. **Layout constraint (verified):** `engine/` and `templates/` MUST be siblings. `resolveDefaultTemplatesDir` walks `../../` from `engine/workflows/` and `run.ts` walks `../` from `engine/run.ts` — both resolve to `<hub>/templates/prompts` ONLY if templates live beside engine. Do NOT nest templates under engine/.
3. Verify no absolute paths or producer-repo assumptions in engine code (grep for `ctrlshft-public`, `$HOME/dev/clients`, `SANDBOX_PRODUCER`).
4. Add engine test suite to hub CI: `.github/workflows/engine-ci.yml` (runs `pnpm exec tsx --test` over `engine/test/` on every PR to hub).
5. Confirm the full suite passes in the hub context (336 engine tests).
Acceptance criteria: `engine/` in hub passes the full test suite in hub CI; no producer-absolute-path references; `templates/` resolves from engine via `../../` (a smoke test invoking `resolveDefaultTemplatesDir` from a workflow module passes).
Feedback loops: `pnpm exec tsx --test` in `engine/`, hub CI run.

---

### ☐ S3: Move templates, scripts, hooks, labels into hub
Type: AFK
Size: M
Blocked by: S1
Steps:
1. Copy `ctrlshft-public/shft/templates/` → `ctrlshft-hub/templates/` (prompts/ 14, extractions/ 6, scripts/, hooks/, copilot-setup-steps.yml).
2. Copy `ctrlshft-public/shft/templates/scripts/` → `ctrlshft-hub/scripts/` (proxy_preflight.sh, check-workflow-enabled.sh, probes, tests).
3. Copy `labels.json` → `ctrlshft-hub/labels.json`.
4. Copy hooks (`block-npx-tsc.sh`, `guard-sandcastle-gitflow.sh`) → `ctrlshft-hub/hooks/`.
5. Fix any relative-path assumptions in scripts (they must run against the consumer workspace, not the hub).
6. Add `hub/release.sh`: reads `hub-version.json` template, bumps `lastPinnedSha` to hub latest, tags `vX.Y.Z`.
Acceptance criteria: All template/script/label/hook files exist in hub; scripts pass shellcheck; release.sh dry-runs cleanly.
Feedback loops: `shellcheck`, `bash -n` on release.sh, dry-run.

---

### ☐ S4: Author `agent-run` composite action
Type: HITL (engine-run semantics need validation)
Size: L
Blocked by: S2, S3
Steps:
1. Create `ctrlshft-hub/actions/agent-run/action.yml` (composite) with inputs: `workflow`, `ref` (default main), `token`, `timeout-minutes`, `extra-args`.
2. Inside the action:
   - Step A: checkout hub at `ref` into `${{ runner.temp }}/ctrlshft-hub` (uses `actions/checkout` with the hub repo + pinned ref).
   - Step B: workflow-enabled check — run `bash <hub>/engine/scripts/check-workflow-enabled.sh <workflow>` with **cwd = consumer workspace** (reads consumer `sandcastle.config.json` `disabledWorkflows`).
   - Step C: proxy preflight (LITELLM envs from consumer secrets).
   - Step D: engine install + run — **cwd = consumer workspace**, `cd ${{ runner.temp }}/ctrlshft-hub/engine && pnpm --ignore-workspace exec tsx run.ts <workflow> --repo ${{ github.workspace }} <extra-args>`. The `--repo` flag is REQUIRED (verified: `run.ts` defaults repoDir to the hub checkout, not the consumer).
   - Step E: publish (issue create / PR update per workflow output).
   - Step F: summarize run to step summary.
3. Port the retry-once loop from the current workflows.
4. Smoke test: run a workflow against a throwaway consumer checkout and confirm templates resolve from `<hub>/templates/prompts` (NOT the consumer repo) and config resolves from the consumer workspace.
Acceptance criteria: `agent-run` action exists; runs the engine against a consumer checkout via `--repo`; emits output file + summary; templates resolve from hub, config from consumer.
Feedback loops: `actionlint`, dry-run with a test consumer.

---

### ☐ S5: Author reusable lifecycle workflows
Type: HITL (depends on S4 semantics)
Size: L
Blocked by: S4
Steps:
1. Create `.github/workflows/agent-plan-issue.yml`, `agent-implement-*.yml`, `agent-review-*.yml` as reusable (`workflow_call`) workflows that delegate to `agent-run`.
2. Each defines `on: workflow_call` with `workflow`, `ref`, `secrets` (AGENT_PAT, LITELLM_*, ANTHROPIC_*).
3. Add `sandcastle-drift.yml` in hub form: check consumers' `hub-version.json` vs hub latest `main`.
4. Keep the simple scheduled agents as thin inline stubs (architecture-review, repo-hygiene, keep-tests-tight) calling `agent-run` directly.
Acceptance criteria: Reusable workflows accept workflow_call; stub workflows reference hub actions; drift check produces SHA-drift PRs, not file diffs.
Feedback loops: `actionlint`, `gh workflow run --dry-run`.

---

### ☐ S6: Pilot — migrate `cmd-public`
Type: HITL (touches the user's main dogfood repo; requires baseline comparison)
Size: L
Blocked by: S4, S5
Steps:
1. In `cmd-public`, delete vendored `.sandcastle/` (84 files), `.github/actions/`, and the 17 workflow YAMLs (keep `sandcastle.config.json`, `CONTEXT.md`, project prompts).
2. Add `.sandcastle/hub-version.json` = `{ "ref": "main", "lastPinnedSha": <hub latest>, "reviewedAt": "<today>" }`.
3. Add N stub workflows (`agent-*.yml`, ~3 lines each, `uses: arndvs/ctrlshft-hub/.sandcastle/actions/agent-run@main`).
4. Baseline-compare: run the full workflow set and confirm outputs/labels/issue creation match the pre-migration behavior.
5. Keep `sandcastle-drift.yml` (now SHA-drift) and `require-regression-guard.yml` (if consumer-owned).
Acceptance criteria: `cmd-public` has no vendored engine; all 17 agents trigger and produce equivalent results; no drift PRs after 1 week.
Feedback loops: `git ls-files .sandcastle` (should be ~0), workflow runs, drift workflow green.

---

### ☐ S7: Rollout to remaining 7 consumers
Type: AFK (mechanical, pilot-proven)
Size: L
Blocked by: S6 (after 1–2 week observation)
Steps:
1. Apply the S6 migration to: launch, aligned, PUSH, mcrdse-ops, rise-awake, arndvs, claude-code-copilot.
2. Preserve each consumer's `sandcastle.config.json`, CONTEXT.md, project prompts, secrets, and any consumer-owned workflows (e.g., claude-code-copilot's proxy-canary customization).
3. Remove each consumer's vendored `.sandcastle/` and `.github/actions/{sandcastle-setup,sandcastle-teardown}`.
4. Add `hub-version.json` per consumer.
5. Add SHA-drift workflow per consumer.
Acceptance criteria: All 8 consumers have zero vendored engine files; all stubs reference the hub; all drift workflows are SHA-drift.
Feedback loops: `git ls-files .sandcastle | wc -l` == ~2 per consumer, workflow runs.

---

### ☐ S8: Retire consumer-side `update-sandcastle.sh`
Type: AFK
Size: S
Blocked by: S7
Steps:
1. In `dotfiles/bin/update-sandcastle.sh`, replace the vendoring body with a pointer to `hub/release.sh` (or delete, per maintainer preference).
2. Update `ctrl` CLI help/docs to reference hub release flow.
3. Remove `.sandcastle-version` manifest generation from consumer flows.
Acceptance criteria: No consumer references `update-sandcastle.sh` for vendoring; docs point to hub release.
Feedback loops: `grep -r update-sandcastle` in consumers, docs review.

---

### ☐ S9: Update producer docs + delegation
Type: HITL (narrative + portfolio quality)
Size: M
Blocked by: S7
Steps:
1. Update `ctrlshft-public` `docs/ARCHITECTURE.md` to show the hub as the engine home (point to `arndvs/ctrlshft-hub`).
2. Update `docs/adr/ADR-008-ctrlshft-hub.md` status from Proposed → Accepted.
3. Update `README.md` (producer) engine section → "engine now lives in ctrlshft-hub".
4. Update hub `README.md` with architecture diagram (C4 context + container from the architecture doc), quick-start, and contribution guide.
5. Update `CONTEXT.md`/handoff to reflect the new topology.
Acceptance criteria: No doc references the old vendored-engine model as current; hub README is a clean portfolio entry point.
Feedback loops: doc review, link check.

---

## 4. Key Insights

```
Critical Principle: Distribution must reference, never copy.
Why it matters: The 84-file vendored engine failed not from any single bug
  but from the structural fact that 8 repos each held a mutable copy of the
  same source tree — drift was guaranteed, and every mitigation (scope
  exclusions, disabledWorkflows, CI gates) was a band-aid over the copy.
How to apply: The hub is the only copy. Consumers hold config + stubs +
  a SHA-lock. All engine code resolves from the hub checkout at a pinned ref.
Risk if ignored: Any re-copy (subtree, mirror, partial vendor) re-introduces
  the exact drift class we are eliminating.
```

```
Critical Principle: The engine was ALREADY designed for a sibling hub layout —
  verified against source, no engine rewrite needed.
Why it matters: resolveDefaultTemplatesDir walks UP from the workflow module:
  <hub>/engine/workflows/ → ../../templates/prompts = <hub>/templates/prompts.
  run.ts computes templatesDir as <run.ts-dir>/templates/prompts =
  <hub>/engine/templates/prompts = <hub>/templates/prompts. Same target.
  The hub layout (engine/ + templates/ as siblings) satisfies BOTH resolvers
  with zero code change.
How to apply: Hub layout MUST be: engine/ (workflows, lib, schemas, run.ts)
  and templates/ (prompts, extractions) as siblings. Do NOT nest templates
  inside engine/ — that breaks the ../../ resolution.
Risk if ignored: Nesting templates under engine/ throws
  "[sandcastle] Unable to locate prompt templates" at module load.
```

```
Critical Principle: repoDir is NEVER inferred from the engine location in hub
  mode — it must be injected via --repo.
Why it matters: run.ts defaults repoDir = path.resolve(__dirname, "..") which
  in hub mode resolves to the HUB checkout, not the consumer. All workflows
  take repoDir as an explicit param (verified in dispatch.ts + every runner),
  and parse-cli-args.ts supports --repo <path>.
How to apply: Hub action MUST invoke:
  pnpm --ignore-workspace exec tsx run.ts <workflow> --repo ${{ github.workspace }} <args>
  with cwd = consumer workspace (for scripts that read sandcastle.config.json
  relative to cwd, e.g. check-workflow-enabled.sh).
Risk if ignored: Engine would operate on the hub repo instead of the consumer
  — wrong git context, wrong issues, wrong config.
```

```
Critical Principle: @main for velocity, SHA-lock for stability.
Why it matters: Consumers want instant engine updates (no re-vendor step),
  but a bad push to hub main would break all consumers at once.
How to apply: Default ref = main; the SHA-drift workflow opens a review PR
  when a consumer's hub-version.json is stale; consumers can pin a SHA or
  vX.Y.Z tag for stability.
Risk if ignored: @main-only without review = instability cascade;
  tag-only without @main = re-introduces versioning ceremony.
```

---

## 5. Dependency Graph

```
S1 (create hub repo)
 └─▶ S2 (engine) ─┐
 └─▶ S3 (templates) ─┤
                     ├─▶ S4 (agent-run action) ─▶ S5 (reusable workflows)
                                          │             │
                                          └──────┬──────┘
                                                 ▼
                                            S6 (pilot cmd-public)
                                                 ▼
                                            S7 (rollout 7 consumers)
                                                 ▼
                                            S8 (retire update-sandcastle.sh)
                                                 ▼
                                            S9 (docs + delegation)  [HITL]
```

Parallel-safe:
- **S1 → S2, S3** can run in parallel after S1 (two independent moves).
- **S4 depends on S2+S3** (action needs engine + templates in place).
- **S6 blocks S7** (pilot before rollout). S8, S9 block S7.

Critical path: `S1 → S2/S3 → S4 → S5 → S6 → S7 → S8/S9`.

---

## 6. QA Plan (final HITL slice)

After S8/S9:

1. **Consumer audit:** for each of the 8 consumers, verify `git ls-files .sandcastle` contains only `hub-version.json` (+ any consumer-owned prompt overrides); no engine lib/workflows/scripts tracked.
2. **Live workflow test:** trigger `workflow_dispatch` on at least one agent per consumer (architecture-review on cmd-public, keep-tests-tight on arndvs, etc.) and confirm the run output, labels, and any issue/PR creation match pre-migration baselines.
3. **Drift test:** simulate a hub `main` push (add a benign commit, e.g. a README tweak), confirm SHA-drift workflows open review PRs (not file-diff re-vendors) within the next scheduled window.
4. **Pin test:** pin one consumer's `hub-version.json` to a fixed SHA, confirm it does NOT pick up the newer hub main.
5. **Recovery test:** revert one consumer to `@main`, confirm it picks up hub latest.
6. **Portfolio review:** open the public hub README — does it stand alone as a documented, senior-engineered artifact for recruiters/clients? (This is the user's explicit goal.)

All green → mark ADR-008 Accepted, archive this plan.

---
