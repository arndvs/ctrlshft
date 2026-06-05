# CVM Lift — Implementation Plan

> **PRD:** `plans/prd-sandcastle-extraction.md`
> **Research:** CVM deep audit (3× researcher-opus, session 2026-06-03)
> **Open issues:** #95 (engine QA), #109 (copilot review loop QA)
> **Key files:** `shft/engine/`, `shft/templates/`, `bin/init-sandcastle.sh`
> **CVM source:** `~/dev/ops/video/course-video-manager/.sandcastle/`

## 1. Context

The first extraction pass ported all shared TypeScript infrastructure (retry wrappers, diff parsers, scoring, dispatch — 14 lib modules, 4 workflows, 3 schemas, 107 tests). This second pass lifts the remaining generic pieces from `course-video-manager/.sandcastle/`: three missing workflow runners + their YAML templates, extraction prompts, output schemas, cross-cutting workflow patterns (AGENT_PAT fallback, force-with-lease, shape detection), the Docker sandbox kit, developer tooling scripts, and platform documentation. Together these complete the platform so any repo can adopt the full AFK agent pipeline via `ctrl init-sandcastle`.

## 2. Design Decisions

| Decision | Choice |
|---|---|
| Runner consolidation | Merge `write-pr.ts` and `write-prd-pr.ts` into a single `write-pr.ts` parameterized by issue shape (has sub-issues → PRD mode, else → plain PR mode) |
| `required()`/`fail()`/`sh()` helpers | Extract to `shft/engine/lib/shell-helpers.ts` — every CVM runner duplicates these; engine runners will import from one place |
| Auth token env var | Standardize on `CLAUDE_CODE_OAUTH_TOKEN` in runners (CVM pattern). Workflow YAMLs pass it from `secrets.CLAUDE_CODE_OAUTH_TOKEN`. Consumer repos that use `ANTHROPIC_API_KEY` configure that in their `sandcastle.config.ts` |
| Extraction prompts | Store in `shft/templates/extractions/` alongside prompts. Runners resolve via `resolvePrompt()` + override pattern already in place |
| Docker sandbox | Template at `shft/templates/sandbox/` with parameterized commit prefix. Not vendored by `init-sandcastle` by default — opt-in via `--sandbox docker` flag |
| Platform docs | Generic versions go to `shft/docs/`. Domain-specific CVM ADRs stay in CVM |
| `architecture-review` workflow | LOW priority — nice-to-have, not blocking platform adoption |
| `agent:blocked` error handling | Backport into existing workflow YAMLs (label + failure file pattern) |
| `pull_request_target` migration | Backport into `agent-fix-pr-feedback.yml` and `agent-review-issue.yml` where applicable |
| Prompt skeletons in docs | Genericize CVM's `docs/agents/prompts/*.prompt.md` → `shft/docs/prompts/` as reference documentation (not templates consumed by runners) |
| AGENT_PAT fallback | Add `${{ secrets.AGENT_PAT || secrets.GITHUB_TOKEN }}` pattern to all workflow YAMLs that add labels triggering downstream workflows |

## 3. Vertical Slices

```
☐ SLICE 1: Shell Helpers Extraction
Type: AFK
Size: S
Blocked by: none
Steps:
  1. Create `shft/engine/lib/shell-helpers.ts` with `required()`, `fail()`, `sh()`, `safeSh()` extracted from CVM runners
  2. Create `shft/engine/lib/shell-helpers.test.ts` with unit tests (missing env → throw, sh() executes, safeSh() returns null on failure)
  3. Update existing engine workflows (`address-review.ts`, `implement-pr.ts`, `review.ts`, `to-issues-prd.ts`) to import from shell-helpers if they duplicate these patterns
  4. Run `npx vitest run` — all 107+ tests pass
Acceptance criteria: `shell-helpers.ts` exports `required`, `fail`, `sh`, `safeSh`; all existing tests still pass; new tests cover each function
Feedback loops: vitest, tsc --noEmit
```

```
☐ SLICE 2: Extraction Prompts + Output Schemas
Type: AFK
Size: M
Blocked by: none
Steps:
  1. Create `shft/templates/extractions/review.md` — genericized from CVM's `.sandcastle/review/extraction.md`
  2. Create `shft/templates/extractions/implement-pr.md` — from CVM's `.sandcastle/implement-pr/extraction.md`
  3. Create `shft/templates/extractions/update-branch.md` — from CVM's `.sandcastle/update-branch/extraction.md`
  4. Create `shft/templates/extractions/architecture-review.md` — from CVM's `.sandcastle/architecture-review/extraction.md`
  5. Create `shft/engine/schemas/update-branch-output.ts` — Zod schema for update-branch comment output
  6. Create `shft/engine/schemas/write-pr-output.ts` — Zod schema for PR title + description
  7. Create `shft/engine/schemas/architecture-review-output.ts` — Zod schema (proposed | skipped)
  8. Verify existing `review-output.ts` and `implement-pr-output.ts` schemas match CVM versions (check `side` field drift)
Acceptance criteria: 4 extraction prompts exist, 3 new schemas export Zod objects, no schema drift between engine and CVM
Feedback loops: tsc --noEmit
```

```
☐ SLICE 3: update-branch Runner + Workflow YAML
Type: AFK
Size: M
Blocked by: Slice 1 (shell-helpers)
Steps:
  1. Create `shft/engine/workflows/update-branch.ts` — port from CVM, import `required`/`sh` from shell-helpers, import `runWithExtraction` from engine lib, parameterize model via config
  2. Create `shft/templates/prompts/update-branch.md` — genericize CVM's `.sandcastle/update-branch/prompt.md`
  3. Create `shft/templates/workflows/agent-update-branch.yml` — port from CVM, use `pull_request_target`, include AGENT_PAT fallback, force-with-lease push, `agent:blocked` error label on failure
  4. Update `shft/templates/labels.json` — add `agent:update-branch` label if missing
  5. Update `bin/init-sandcastle.sh` — include `agent-update-branch.yml` in workflow copy step
Acceptance criteria: Runner compiles clean, YAML is repo-agnostic (no hardcoded repo refs), init-sandcastle vendors it
Feedback loops: tsc --noEmit, shellcheck on init-sandcastle.sh
```

```
☐ SLICE 4: write-pr Runner + Workflow YAML
Type: AFK
Size: M
Blocked by: Slice 1 (shell-helpers)
Steps:
  1. Create `shft/engine/workflows/write-pr.ts` — merge CVM's `write-pr.ts` and `write-prd-pr.ts` into single parameterized runner. Detect PRD mode via presence of `SUB_ISSUE_NUMBER` env var
  2. Create `shft/templates/prompts/write-pr.md` — genericize from CVM prompt
  3. No new YAML — write-pr is invoked as a step within `agent-implement-issue.yml` and `agent-implement-prd.yml`, not standalone
Acceptance criteria: Runner compiles clean, handles both plain-PR and PRD-PR modes, uses `runWithRetry` from engine lib
Feedback loops: tsc --noEmit
```

```
☐ SLICE 5: implement-prd Runner + Workflow YAML
Type: AFK
Size: L
Blocked by: Slice 1, Slice 4 (write-pr used as step)
Steps:
  1. Create `shft/engine/workflows/implement-prd.ts` — port from CVM, parameterize model via config, import shell-helpers
  2. Create `shft/templates/prompts/implement-prd.md` — genericize CVM's `.sandcastle/implement-prd/prompt.md`
  3. Create `shft/templates/workflows/agent-implement-prd.yml` — port from CVM. Includes:
     - Shape detection (sub-issues + parent check, reject nested PRDs)
     - Sub-issue iteration loop with `agent:implement` self-chaining via AGENT_PAT
     - `agent:blocked` on failure
     - Force-with-lease push
  4. Update `shft/templates/labels.json` — add any missing labels (agent:queued if not present)
  5. Update `bin/init-sandcastle.sh` — include `agent-implement-prd.yml` in workflow copy step
Acceptance criteria: Runner compiles clean, YAML handles full sub-issue loop, nested-PRD rejection works, init-sandcastle vendors it
Feedback loops: tsc --noEmit, shellcheck
```

```
☐ SLICE 6: promote-queued Workflow YAML
Type: AFK
Size: S
Blocked by: none
Steps:
  1. Create `shft/templates/workflows/agent-promote-queued.yml` — port from CVM. This is pure shell (no TypeScript runner). Genericize any hardcoded values. Uses AGENT_PAT for label swap.
  2. Update `shft/templates/labels.json` — add `agent:queued` label
  3. Update `bin/init-sandcastle.sh` — include `agent-promote-queued.yml` in workflow copy step
Acceptance criteria: YAML is repo-agnostic, correctly evaluates dependency graph via GraphQL `blocking` field, promotes when all blockers closed
Feedback loops: shellcheck, yamllint
```

```
☐ SLICE 7: Cross-Cutting YAML Pattern Backport
Type: AFK
Size: M
Blocked by: none
Steps:
  1. Audit all 6 existing `shft/templates/workflows/agent-*.yml` for missing patterns
  2. Add AGENT_PAT fallback (`${{ secrets.AGENT_PAT || secrets.GITHUB_TOKEN }}`) to any workflow that adds labels triggering downstream workflows
  3. Add `agent:blocked` error label on failure steps where missing
  4. Migrate applicable workflows from `pull_request` to `pull_request_target` trigger where the CVM pattern proves more reliable
  5. Add force-with-lease push pattern where workflows push to PR branches
  6. Standardize concurrency groups (`agent-mutate-pr-*` for PR-mutating workflows)
Acceptance criteria: All workflow YAMLs use consistent patterns; no workflow uses bare `GITHUB_TOKEN` for label operations that trigger other workflows
Feedback loops: yamllint, diff review
```

```
☐ SLICE 8: Docker Sandbox Template
Type: AFK
Size: S
Blocked by: none
Steps:
  1. Create `shft/templates/sandbox/Dockerfile` — genericize from CVM, parameterize package manager (npm/pnpm)
  2. Create `shft/templates/sandbox/README.md` — usage instructions (how to opt-in via `--sandbox docker`)
  3. DO NOT wire into init-sandcastle yet — this is opt-in only
Acceptance criteria: Dockerfile builds successfully with `docker build`, README documents usage
Feedback loops: docker build (manual, HITL)
```

```
☐ SLICE 9: Developer Tooling Scripts
Type: AFK
Size: S
Blocked by: none
Steps:
  1. Create `shft/templates/scripts/check-file-tokens.sh` — genericize from CVM's `scripts/check-file-tokens.sh`
  2. Create `shft/templates/scripts/setup-github-secrets.sh` — genericize from CVM's `scripts/setup-github-secrets.sh` (parameterize secret names)
  3. Create `shft/templates/hooks/block-npx-tsc.sh` — genericize from CVM's `.claude/hooks/block-npx-tsc.sh`
  4. Update `bin/init-sandcastle.sh` — optionally copy scripts/ and hooks/ (behind `--with-scripts` flag or always)
Acceptance criteria: Scripts are repo-agnostic, shellcheck clean, init-sandcastle can vendor them
Feedback loops: shellcheck
```

```
☐ SLICE 10: Platform Documentation
Type: AFK
Size: M
Blocked by: Slices 3-6 (need final workflow list)
Steps:
  1. Create `shft/docs/platform-spec.md` — genericize CVM's `docs/agents/afk-agent-platform-spec.md`. Remove all CVM domain references
  2. Create `shft/docs/triage-labels.md` — genericize CVM's label mapping doc
  3. Create `shft/docs/backlog.md` — genericize CVM's backlog conventions doc
  4. Create `shft/docs/zero-commit-runs.md` — genericize ADR-0008 from CVM
  5. Create 9 prompt skeleton docs in `shft/docs/prompts/` — genericize CVM's `docs/agents/prompts/*.prompt.md`. These are reference docs showing prompt structure, not runtime templates
  6. Update `shft/README.md` — add platform overview, link to docs, list all workflows
Acceptance criteria: All docs are generic (no CVM domain terms), README covers full platform
Feedback loops: prose review (HITL)
```

```
☐ SLICE 11: init-sandcastle Updates
Type: AFK
Size: S
Blocked by: Slices 3, 5, 6, 9
Steps:
  1. Update `bin/init-sandcastle.sh` to vendor all new workflow YAMLs (update-branch, implement-prd, promote-queued)
  2. Update label creation to include any new labels from `labels.json`
  3. Add `--with-scripts` flag to optionally copy developer tooling scripts
  4. Add `--sandbox docker` flag to optionally copy Docker sandbox template
  5. Test idempotency — running init twice doesn't duplicate or corrupt
Acceptance criteria: `init-sandcastle --help` shows new flags, fresh init includes all 9+ workflow YAMLs, idempotent
Feedback loops: shellcheck, manual run in scratch dir
```

```
☐ SLICE 12: Architecture Review Runner (LOW)
Type: AFK
Size: M
Blocked by: Slices 1, 2
Steps:
  1. Create `shft/engine/workflows/architecture-review.ts` — port from CVM
  2. Create `shft/templates/prompts/architecture-review.md` — genericize prompt
  3. Create `shft/templates/workflows/agent-architecture-review.yml` — port from CVM
  4. Update init-sandcastle to include it (opt-in or always)
Acceptance criteria: Runner compiles clean, YAML is repo-agnostic
Feedback loops: tsc --noEmit
```

```
☐ SLICE 13: CVM Migration (Consuming Repo)
Type: HITL
Size: L
Blocked by: Slices 1-11
Steps:
  1. Run `ctrl update-sandcastle` in course-video-manager
  2. Replace CVM's `.sandcastle/` runners with vendored engine copies
  3. Verify all 7 agent-*.yml workflows still trigger correctly
  4. Verify CVM-specific prompt overrides in `.sandcastle/prompts/` are respected
  5. Remove duplicated infrastructure from CVM (retry wrappers, helpers, schemas now in engine)
  6. Run full CI pipeline — no regressions
  7. Manual: create test issue, verify agent-implement flow end-to-end
Acceptance criteria: CVM uses zero duplicated infrastructure from dotfiles engine; all workflows function; no regressions
Feedback loops: CI green, manual E2E test
```

```
☐ SLICE 14: Final QA
Type: HITL
Size: L
Blocked by: Slice 13
Steps:
  1. Execute all 4 test scenarios from `plans/issues/11-qa-validation.md`
  2. Execute all 5 test scenarios from issue #109
  3. Verify `ctrl init-sandcastle` in a fresh scratch repo produces complete working pipeline
  4. Verify `ctrl update-sandcastle` detects drift and patches correctly
  5. Close issues #95 and #109
  6. Clean up: delete `plans/issues/11-qa-validation.md`, archive `plans/prd-sandcastle-extraction.md`
Acceptance criteria: All QA scenarios pass, no open issues remain, plan files archived
Feedback loops: manual E2E testing
```

## 4. Key Insights

```
Critical Principle: AGENT_PAT is required for label-chaining workflows
Why it matters: Labels added via GITHUB_TOKEN don't trigger downstream workflows. The implement → review → merge chain breaks without AGENT_PAT.
How to apply: All workflow YAMLs that add labels triggering other workflows must use `${{ secrets.AGENT_PAT || secrets.GITHUB_TOKEN }}` for the GH_TOKEN env var used in label operations.
Risk if ignored: Silent workflow chain breakage — agent:implement label gets added but agent-implement.yml never fires.
```

```
Critical Principle: pull_request_target over pull_request for label-triggered PR workflows
Why it matters: The standard `pull_request` trigger depends on a generated merge commit, which GitHub fails to produce when the PR is out-of-date or conflicting — exactly when update-branch and implement-pr need to run.
How to apply: Any workflow triggered by PR labels that mutates the PR branch should use `pull_request_target`.
Risk if ignored: Workflows silently don't trigger on PRs with merge conflicts.
```

```
Critical Principle: Force-with-lease push guards concurrency
Why it matters: Multiple workflows can target the same PR branch. `--force-with-lease` against the checkout SHA prevents one workflow from overwriting another's work.
How to apply: Every push step must use `git push --force-with-lease=<branch>:<expected-sha>` where expected-sha is the SHA at checkout time.
Risk if ignored: Race condition — concurrent workflow overwrites commits from another.
```

```
Critical Principle: Shape detection prevents infinite recursion
Why it matters: implement-prd self-chains by re-applying `agent:implement` to each sub-issue. Without shape detection, a nested PRD could recurse infinitely.
How to apply: Before entering the sub-issue loop, check that no sub-issue itself has sub-issues. Reject with `agent:blocked` label if nested.
Risk if ignored: Infinite workflow recursion, burning CI minutes and creating garbage branches.
```

## 5. Dependency Graph

```
                    ┌──────────────────────────────────┐
                    │          Slice 1: shell-helpers   │
                    └──────┬───────────┬───────────────┘
                           │           │
              ┌────────────▼──┐   ┌────▼───────────────┐
              │ Slice 3:      │   │ Slice 4:           │
              │ update-branch │   │ write-pr           │
              └──────┬────────┘   └────┬───────────────┘
                     │                 │
                     │            ┌────▼───────────────┐
                     │            │ Slice 5:           │
                     │            │ implement-prd      │
                     │            └────┬───────────────┘
                     │                 │
    ┌────────────────┴─────────────────┘
    │
    │  ┌────────────────────────┐   (parallel, no deps)
    │  │ Slice 2: extractions   │
    │  │ Slice 6: promote-queue │
    │  │ Slice 7: YAML backport │
    │  │ Slice 8: Docker        │
    │  │ Slice 9: scripts       │
    │  └────────────────────────┘
    │
    ├──────────────────────┐
    │                      │
    ▼                      ▼
┌─────────────────┐  ┌──────────────────┐
│ Slice 10: docs  │  │ Slice 11: init   │
│ (needs 3-6)     │  │ (needs 3,5,6,9)  │
└────────┬────────┘  └────────┬─────────┘
         │                    │
         │  ┌─────────────────┘
         │  │
         ▼  ▼
┌────────────────────┐
│ Slice 12: arch-rev │ (LOW — optional)
├────────────────────┤
│ Slice 13: CVM      │ (HITL)
│ migration          │
├────────────────────┤
│ Slice 14: Final QA │ (HITL)
└────────────────────┘
```

**Parallel-safe groups:**
- **Wave 1** (no deps): Slices 1, 2, 6, 7, 8, 9
- **Wave 2** (after Slice 1): Slices 3, 4
- **Wave 3** (after Slice 4): Slice 5
- **Wave 4** (after Waves 1-3): Slices 10, 11
- **Wave 5** (after all): Slices 12 (optional), 13, 14

## 6. QA Plan

See **Slice 14** above. Additionally:

- **Regression gate:** Every AFK slice must leave `npx vitest run` green and `tsc --noEmit` clean before commit
- **Shell quality:** Every `.sh` file must pass `shellcheck`
- **YAML quality:** Every `.yml` file must have valid YAML syntax
- **CVM smoke test (Slice 13):** Create a real issue in CVM, verify the full label state machine (implement → review → merge) fires correctly with the new vendored engine
- **Fresh repo smoke test (Slice 14):** `ctrl init-sandcastle` in a blank repo, create an issue with `Sandcastle` label, verify workflow triggers
- **Close open issues:** #95 and #109 after manual verification passes
