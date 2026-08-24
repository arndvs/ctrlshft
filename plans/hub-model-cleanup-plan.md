# Architecture Plan — Hub-Model Completion & Cross-Repo Reconciliation

**Status:** Proposed — awaiting approval
**Date:** 2026-08-20
**Derived from:** `docs/sandcastle-hub-architecture.md`, `docs/adr/ADR-008-sandcastle-hub.md`, `sandcastle-hub/docs/adr/ADR-001-hub-single-source.md`
**Executed by:** AFK agents (shft) for AFK slices; human for HITL slices

---

## 1. Context

The hub-model migration is functionally complete: the producer (ctrlshft-public)
removed its vendored engine, and consumers reference `arndvs/sandcastle-hub`
remotely. This session fixed the producer's stale smoke-coverage test, rebuilt
its `shft/templates/workflows/*` as hub stubs, deleted its stale composite
actions and `sandcastle-ci.yml`, and synced everything across dotfiles + public
+ copilot.

But the migration exposed **four unresolved structural gaps** — the same
stale-template pattern the producer just fixed, still present in the hub itself,
plus a cross-repo divergence in shared tooling:

1. **Hub templates are still old-model.** The hub's `templates/workflows/`
   contains 11/12 agent workflows + `sandcastle-ci.yml` + `labels-sync.yml`
   that encode the vendored engine model (`.sandcastle/engine`,
   `pnpm --ignore-workspace exec tsx ../run.ts`, local composite actions) —
   the exact pattern ADR-001 says is dead. These are the canonical templates
   consumers receive via `init-sandcastle.sh` (via the producer's
   `SANDBOX_PRODUCER` resolution), so new installs would produce broken
   engine-referencing workflows from the hub itself.
2. **Hub | `sandcastle-ci.yml` template is stale.** It validates the vendored
   engine (`.sandcastle/engine/**`, `pnpm install --frozen-lockfile`). The hub
   owns engine CI in `.github/workflows/engine-ci.yml`; the consumer-side
   `sandcastle-ci.yml` template is a dead artifact of the old model.
3. **Cross-repo | `bin/ctrl`, `bin/preflight-sandcastle.sh`, `bin/bootstrap.sh`
   diverged between dotfiles and public.** Public has newer SaaS-governance /
   worktree-bridge changes (`697435c`, PR #318) and the modern
   `working/runtime` paths; dotfiles has the hub-model preflight drift-check
   and `_vendor` path fixes (commits `a8178d7`, `3c29751`). Neither repo has
   both sets of changes. This is a genuine 3-way merge that will keep biting
   every `ctrl sync` until resolved.
4. **Hub | no structural QA gate.** The hub has no test/ directory at all. The
   producer's `test/sandcastle-smoke-coverage.sh` validates consumer templates;
   the hub needs an equivalent gate that validates *its own* installed
   workflows + templates are hub-model-clean, so the drift pattern in (1)
   can never regress.

---

## 2. Design Decisions

| Decision | Choice | Rationale |
| --- | --- | --- |
| Hub template home | **`templates/workflows/` is the canonical stub source** — rebuild as thin hub stubs | It's the "one place the templates live" per README/ADR-001; consumers + producer copy from it. It must encode the hub stub contract, not the old engine contract. |
| `sandcastle-ci.yml` in hub templates | **Delete** | The hub owns engine CI (`engine-ci.yml`); the dispatch-module-resolution double-check lives there. No consumer needs a local engine-validating CI anymore. |
| Hub `.github/workflows/` | **Keep as-is** (already hub-model) | Self-dogfood workflows (`agent-architecture-review.yml`, `agent-repo-hygiene.yml`) are correct thin stubs. |
| Producer templates sync direction | **Producer (`shft/templates/`) pulls FROM hub (`templates/`)** | Both must match; hub is the single source of truth for the stub contract. Producer mirrors hub rather than diverging. |
| `bin/ctrl` / `preflight` / `bootstrap` 3-way merge | **Feature-branch merge with explicit resolution** — create `work/sync-tooling` in *public*, merge dotfiles' sandcastle changes INTO public's battery of newer changes, then pull merged result back to dotfiles | Public is master per REPO_TOPOLOGY. Merge dotfiles' sandbox-hub-model bits into public's newer bridge/worktree/runtime bits; resolve conflicts once. |
| Hub QA gate | **`test/hub-smoke-coverage.sh`** (mirror of producer's) validating hub templates + installed workflows | Structural drift guard so the stale-template pattern cannot silently return. |
| Sync tooling | **Keep `sync-public-repo.sh` (private → public) but extend it** so it also pulls accepted hub-model changes to dotfiles | Prevent future 3-way drift between the three nodes. |

---

## 3. Vertical Slices

> Each slice is independently shippable and wires end-to-end. AFK slices run
> fully autonomously; HITL slices need human judgment/access.

---

### ☐ S1: Hub — rebuild template workflows as hub-model stubs
Type: HITL (touches canonical template source; requires review)
Size: M
Blocked by: none
Steps:
1. For each of the 11 stale `templates/workflows/agent-*.yml` on the hub, replace
   the vendored body (.sandcastle/engine, pnpm exec tsx ../run.ts, local
   composite actions, `{{DEFAULT_BRANCH}}` substitutes) with the thin stub
   contract:
   - agent-run style (7): `uses: arndvs/sandcastle-hub/actions/agent-run@main`
     with `workflow: <name>`, `ref: main`, `token:`, optional `extra-args`.
   - reusable-workflow style (6): `jobs: <name>: uses:
     arndvs/sandcastle-hub/.github/workflows/reusable-*.yml@main` with `secrets:
     inherit`.
   - Match the exact stub bodies the producer now uses (see
     `ctrlshft-public/.github/workflows/` for the reference contract).
2. Update `agent-promote-queued.yml` (the one already-hub-model template) if it
   needs the `{{DEFAULT_BRANCH}}` templating substitution marker (it's the one
   template that was already converted — verify against producer's).
3. Delete `templates/workflows/sandcastle-ci.yml` (dead vendored-engine CI).
4. Verify `labels-sync.yml` and `sandcastle-drift.yml` in templates match the
   hub-model installed versions (they reference the hub API, not `.sandcastle/`).
5. Open PR to hub `main`, request review.

Acceptance criteria:
- `grep -L "\.sandcastle/engine\|pnpm --ignore-workspace exec tsx" templates/workflows/agent-*.yml`
  returns nothing (all 12 are stubs).
- `templates/workflows/` has no more `sandcastle-ci.yml`.
- The hub templates diff 1:1 with the producer's `shft/templates/workflows/`
  for the 12 agent workflows.

Feedback loops: `bash -n` on each YAML; `grep -c agent-run templates/workflows/agent-*.yml`;
CI on the PR (hub `engine-ci.yml` still passes).

---

### ☐ S2: Add hub QA gate — test/hub-smoke-coverage.sh
Type: AFK
Size: M
Blocked: S1 (gate validates S1's template state)

Steps:
1. Create `test/hub-smoke-coverage.sh` mirroring the producer's clean
   `test/sandcastle-smoke-coverage.sh` shape (dotfiles version — the 227-line
   template-coverage gate), adapted:
   - `agent_workflow_templates` glob → hub `templates/workflows/agent-*.yml`.
   - Assert every template contains a `sandcastle-hub` reference
     (`agent-run` composite or `reusable-*.yml` call).
   - Assert every template avoids old-model tokens
     (`.sandcastle/engine`, `pnpm --ignore-workspace exec tsx`, `uses:
     ./.github/actions/`).
   - Assert the report-aggregator inventory (if hub has a `SANDCASTLE_WORKFLOWS`
     list) tracks every template.
2. Assert every `reusable-*.yml` in `.github/workflows/` referenced by a
   consumer stub exists.
3. Assert `engine-ci.yml` exists and covers the engine.
4. Wire the gate into a `hub-qa` job (new workflow — `qa-hub-alignment.yml` or
   add a job to existing `engine-ci.yml` buff).

Acceptance:
- `bash test/hub-smoke-coverage.sh` exits 0 with ≥ N passes, 0 failures.
- A commit that reintroduces `.sandcastle/engine` into a template fails the gate.

Feedback: `bash test/hub-smoke-coverage.sh`.

---

### S3: Sync producer templates ↔ hub templates (mirror)
Type: HITL (touches producer + public history)
Size: S
Blocked: S1 (hub templates must be correct first)

Steps:
1. After S1 the hub is the canonical stub source. Copy hub
   `templates/workflows/` → producer `shft/templates/workflows/` (the 12 agent +
   labels-sync + drift; keep producer's `check-attribution`/
   `require-regression-guard` which are producer-owned).
2. Re-run producer `test/sandcastle-smoke-coverage.sh` (35/35) +
   `test/init-sandcastle-proxy-canary.sh` (26/26).
3. Verify `init-sandcastle.sh` (SANDBOX_PRODUCER resolution) renders the stubs
   correctly to `.github/workflows/`.

Acceptance: template dirs diff 1:1 for the shared 16 files; all producer
sandcastle suites still green.

Feedback loops: `bash test/sandcastle-smoke-coverage.sh`;
`bash test/init-sandcastle-proxy-canary.sh`.

---

### S4: Resolve ctrl / preflight / bootstrap 3-way divergence
Type: HITL (merge conflicts need judgment)
Size: L
Blocked: none

Steps:
1. On `dev`, create merge-prep branch `ai/fix/sync-tooling` in the public repo.
2. Merge dotfiles' branches (private remote `private/dev`) into it, resolving:
   - `bin/ctrl`: keep public's newer `worktree|wt` command + bridge
     single-worker lock + `running/runtime` paths; add dotfiles' hub-model
     `update-sandcastle` deprecation routing. Both merge clean.
   - `bin/preflight-sandcastle.sh`: take dotfiles' hub-SHA-drift check (replace
     `_check_engine` vendored-engine check) but keep public's permission-block
     checker (accept top-level + job-level).
   - `bootstrap.sh`: take dotfiles' `_local` skills aggregation + skills-lock
     validation; keep public's `working/runtime` active-client path.
3. Push branch, open PR to `dev`, human merges.
4. Then pull `public/dev` into `dotfiles` (private) `dev`;
   resolve dotfiles-local overlay additions (secrets dir, machine-local).

Acceptance: `diff` between public and dotfiles `bin/ctrl` / `preflight`/
`bootstrap` is empty (except intentionally-private overlay lines).
Feedback: `git diff <public-dev> <dotfiles-dev> -- bin/ | grep -v '^index'` empty.

---

### S5: Extend sync tooling for bidirectional hub sync
Type: HITL
Size: S
Blocked: S4

Steps:
1. Add `sync-hub-repo.sh` (or extend `sync-public-repo.sh`) that copies
   `templates/workflows/` from the hub → producer `shft/templates/workflows/`
   for the 16 shared names (agent-*, labels-sync, sandcastle-drift), skipping
   producer-owned `check-attribution`/`require-regression-guard`.
2. Add a parity check: `diff hub/templates/workflows vs producer` → exit
   non-zero on drift. Wire into CI or the smoke-coverage gate.

Acceptance: a one-command sync aligns hub ↔ producer templates;
a drift-detection script reports misalignment.

Feedback: run the parity check after a phantom hub template change.

---

## 4. Key Insights

    Critical Principle: The hub is the single template contract — templates that
    reference the vendored engine are a lie.
    Why it matters: hub templates flow to every consumer install via
    init-sandcastle; a stale template ships broken workflows to all consumers.
    How to apply: mirror hub templates 1:1 to producer, and add gates on both
    The hub's and producer's CI that fail on old-model tokens.
    Risk if ignored: next `init-sandcastle` round-trip re-introduces the
    vendored engine pattern to every consumer.

    Critical Principle: Cross-repo ctrl/pre-flight/bootstrap drift accumulates
    silently.
    Why it matters: each repo holds a partial copy; `ctrl sync` and the CLI
    behave differently depending on checkout.
    How to apply: 3-way merge once — public-first, dotfiles pull-back — then
    extend sync-public-repo.sh so shared files cannot diverge again.
    Risk if ignored: repeated failed `ctrl sync` sessions and HITL time
    chasing diverged branch states.

---

## 5. Dependency Graph

```
S1 (hub templates → stubs) ──▶ S2 (hub QA gate)
        │
        └──▶ S3 (producer ↔ hub mirror) ──▶ S4 (ctrl/preflight/bootstrap merge)
                                              │
                                              └──▶ S5 (sync tooling bidir)
```

Execution order: S1 → S2 → S3 → S4 → S5. S2 depends solely on S1 (AFK-able).
S4 touches only tooling, independent of S1-S3 — parallel-safe.

- S1 — hub templates (HITL, review)
- S2 — hub QA gate (AFK, blocked from S1)
- S3 — producer mirror (HITL, blocked from S1)
- S4 — ctrl/pref/bootstrap merge (HITL, **parallel-safe with S1-S3**)
- S5 — sync tooling bidir (HITL, blocked from S4 results)

S1 → S2, S1 → S3, S4 ∥ S1..S3, S4 → S5.

---

## 6. QA Plan

The final QA slice (HITL) verifies the whole system after S1-S5 merge:

1. On a fresh consumer (e.g. a throwaway branch of `llm-gateway`),
   run `ctrl init-sandcastle --force` and confirm `.github/workflows/agent-*.yml`
   are thin stubs referencing `arndvs/sandcastle-hub` — no `.sandcastle/engine`,
   no local composite actions.
2. Confirm `templates/workflows` dirs identical between hub and producer.
3. Run producer sandcastle suite: smoke-coverage 35, init 26, report-smoke 15
   all green.
4. Confirm `bin/ctrl update-sandcastle` prints the hub release deprecation
   message identically in both checkout-nodes, and
   `ctrl worktree`-command works in both.
5. Confirm `sync` tooling parity check reports zero drift after a fresh
   hub pull.