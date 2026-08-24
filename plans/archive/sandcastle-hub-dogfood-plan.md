# Sandcastle Hub — Dogfood & Completion Plan
> **Archived** — implemented; see git history for the shipping commits. This plan is kept for reference only.

> **Status:** Proposed — awaiting approval
> **Date:** 2026-08-18
> **Derived from:** `docs/sandcastle-hub-architecture.md` + `docs/adr/ADR-008-sandcastle-hub.md` + `plans/sandcastle-hub-plan.md`
> **Executed by:** AFK agents (shft) for AFK slices; human for HITL slices

---

## 1. Context

The hub model is built and the pilot (cmd-public) is merged to `dev` (PR #19) with a promotion PR open (#20). But three structural gaps remain before the model is complete and self-consistent:

1. **The producer (ctrlshft) still vendors the engine.** It runs the old `.sandcastle/` copy — the exact drift-prone pattern the hub eliminates — and cannot validate the hub model because it never exercises it. The producer must dogfood its own solution.
2. **The hub doesn't dogfood itself.** No architecture-review/repo-hygiene workflows run in the hub, so engine-PRDs have no natural home there. The 21 ctrlshft `source:architecture-review` issues are a mix of engine-scoped (belong in hub) and non-engine (stay in ctrlshft), and can't be cleanly re-provisioned until the hub is a working consumer.
3. **`hub/release.sh` doesn't exist.** The plan calls for it as the replacement for `update-sandcastle.sh` (S8), but it was never built. Without it, the SHA-lock/drift workflow has no release mechanism and `update-sandcastle.sh` can't be retired.

This plan completes the hub model: dogfood ctrlshft on the hub, make the hub a self-dogfooding consumer, build the release tooling, and clean up the issue backlog.

---

## 2. Design Decisions

| Decision | Choice | Rationale |
| --- | --- | --- |
| ctrlshft engine home | **Fully delegate to hub** — remove `shft/engine/` from ctrlshft, keep docs/ADRs pointing at hub | Mirrored copy re-introduces drift (the exact failure we eliminated). Hub is the single engine home. |
| ctrlshft baseBranch | `dev` (unchanged) — hub stubs use `ref: main` for the engine, consumer config keeps `baseBranch: dev` | The engine ref (hub `main`) is independent of the consumer's own base branch. |
| Hub self-dogfood | **Add architecture-review + repo-hygiene to the hub** (schedule + dispatch) | Engine-PRDs get filed in the hub where the engine lives; proves the model on the most important repo. |
| Issue re-provisioning | **No bulk move.** Hub dogfood files new engine-PRDs in the hub; ctrlshft engine-scoped issues close as duplicates → hub equivalents | Bulk move drags non-engine issues into the hub and orphans them until the hub dogfoods. |
| `hub/release.sh` | Build it — bumps `hub-version.json` template, tags `vX.Y.Z`, updates `latest` | Required to retire `update-sandcastle.sh` and give the SHA-drift workflow a release mechanism. |
| `update-sandcastle.sh` | Retire after all consumers migrated + release.sh built | Consumers no longer vendor; the script's drift logic dies. |
| Rollout order | cmd (done) → ctrlshft (dogfood #2) → hub self-dogfood → 5 remaining consumers | Producer first proves the model; hub self-dogfood gives engine-PRDs a home; then mechanical rollout. |
| cmd-private | Stays non-consumer | No sandcastle install. |

---

## 3. Vertical Slices

> Each slice is independently shippable and wires end-to-end. AFK slices run fully autonomously; HITL slices need human judgment/access.

---

### ☐ S1: Merge cmd promotion + validate pilot
Type: HITL (merge + observe)
Size: S
Blocked by: none
Steps:
1. Merge PR #20 (cmd dev→main, hub migration).
2. Trigger `agent-architecture-review` via `workflow_dispatch` on cmd main.
3. Confirm: hub action resolves, engine installs + runs against consumer workspace, templates resolve from hub, config from consumer, output + summary produced.
4. Observe 1–2 weeks: no drift, no engine-change proposals.
Acceptance criteria: cmd runs on the hub end-to-end; zero drift after observation.
Feedback loops: workflow run logs, `git ls-files .sandcastle` (== 2 files).

---

### ☐ S2: Migrate ctrlshft to the hub (dogfood #2)
Type: HITL (touches producer; requires branch + PR review)
Size: L
Blocked by: S1 (pilot proven)
Steps:
1. On a branch in ctrlshft, remove the vendored `.sandcastle/` (engine, templates, scripts, hooks, run.ts, labels, CODING_STANDARDS) — keep `.sandcastle/prompts/` (consumer override) + config.
2. Remove vendored `.github/actions/{sandcastle-setup,sandcastle-teardown}` + vendored workflow YAMLs.
3. Add `.sandcastle/hub-version.json` SHA-lock.
4. Add 12 thin workflow stubs (7 composite-action calls + 5 reusable-workflow calls) referencing `arndvs/sandcastle-hub`.
5. Add SHA-drift + hub-backed labels-sync workflows.
6. **Remove `shft/engine/`** (fully delegate to hub) — update `docs/ARCHITECTURE.md`, `docs/adr/ADR-008`, README to point at hub as engine home.
7. Open PR to `dev` for review.
Acceptance criteria: ctrlshft has no vendored engine; all workflows reference hub; `shft/engine/` removed; docs point at hub.
Feedback loops: `git ls-files .sandcastle` (== 2), workflow runs, doc link check.

---

### ☐ S3: Hub self-dogfood (architecture-review + repo-hygiene in the hub)
Type: AFK
Size: M
Blocked by: S2 (hub is a proven consumer pattern)
Steps:
1. Add `agent-architecture-review.yml` + `agent-repo-hygiene.yml` to the hub's `.github/workflows/` (schedule + dispatch), calling `actions/agent-run` with `workflow: architecture-review` / `repo-hygiene`.
2. Add `sandcastle.config.json` to the hub (model, baseBranch main, promptDir, etc.).
3. Add `CONTEXT.md` + `docs/adr/` to the hub (so the engine has context to review).
4. Ensure `DEFAULT_EXCLUDED_PATHS` in the hub engine excludes the hub's own engine/templates/actions (self-protection).
5. Trigger both workflows; confirm they file engine-PRDs **in the hub**.
Acceptance criteria: Hub runs architecture-review + repo-hygiene on schedule; issues filed in hub with `source:architecture-review` label.
Feedback loops: workflow runs, issue creation.

---

### ☐ S4: Build `hub/release.sh`
Type: AFK
Size: M
Blocked by: none (can run parallel to S2/S3)
Steps:
1. Create `sandcastle-hub/hub/release.sh`:
   - Reads `hub-version.json` template (or generates one).
   - Bumps `lastPinnedSha` to hub latest `main` SHA.
   - Tags `vX.Y.Z` (semver bump via arg or auto-increment).
   - Updates `latest` ref (or documents the tag as the stable pin).
   - Prints the new SHA + tag for consumers to pin.
2. Add `hub/README.md` documenting release flow.
3. Add a `release` workflow (optional) that runs release.sh on tag push.
Acceptance criteria: `release.sh` dry-runs cleanly; tags a version; prints SHA for consumers.
Feedback loops: `bash -n`, dry-run, tag creation.

---

### ☐ S5: Retire `update-sandcastle.sh` (dotfiles)
Type: AFK
Size: S
Blocked by: S4 (release.sh exists), S7 (all consumers migrated)
Steps:
1. In `dotfiles/bin/update-sandcastle.sh`, replace the vendoring body with a pointer to `hub/release.sh` (or delete, per maintainer preference).
2. Update `ctrl` CLI help/docs to reference hub release flow.
3. Remove `.sandcastle-version` manifest generation from consumer flows.
Acceptance criteria: No consumer references `update-sandcastle.sh` for vendoring; docs point to hub release.
Feedback loops: `grep -r update-sandcastle` in consumers, docs review.

---

### ☐ S6: Rollout to remaining 5 consumers
Type: AFK (mechanical, pilot-proven)
Size: L
Blocked by: S1 (pilot proven), S2 (ctrlshft pattern proven)
Steps:
1. Apply the S2 migration to: launch, aligned, PUSH, riseawake.com, claude-code-copilot.
2. Preserve each consumer's `sandcastle.config.json`, CONTEXT.md, project prompts, secrets, consumer-owned workflows.
3. Remove vendored `.sandcastle/` + `.github/actions/{sandcastle-setup,sandcastle-teardown}`.
4. Add `hub-version.json` + SHA-drift + hub-backed labels-sync per consumer.
5. Open PRs per consumer (base = each repo's convention).
Acceptance criteria: All 5 consumers have zero vendored engine files; all stubs reference the hub; drift workflows are SHA-drift.
Feedback loops: `git ls-files .sandcastle | wc -l` == ~2 per consumer, workflow runs.

---

### ☐ S7: Issue backlog cleanup
Type: HITL (judgment on issue disposition)
Size: M
Blocked by: S3 (hub dogfoods → engine-PRDs have a home)
Steps:
1. After hub dogfood files engine-PRDs in the hub, identify ctrlshft `source:architecture-review` issues that are engine-scoped (e.g. #297 GitHubClient, #291 WorkflowContext, #293 address-review scoring, #284 integration tests, #276 pipeline legality, #275 engine unit tests, #311 dead exports).
2. For each, check if a hub equivalent exists (filed by hub dogfood); if so, close ctrlshft issue as duplicate → hub.
3. Leave non-engine issues (HUD, bridge, context-detection) in ctrlshft.
4. Add a note to the architecture doc: "engine-PRDs live in the hub; ctrlshft issues are non-engine."
Acceptance criteria: Engine-scoped issues closed as duplicates → hub; non-engine issues remain; doc updated.
Feedback loops: issue list review, doc check.

---

### ☐ S8: Final QA + docs
Type: HITL
Size: M
Blocked by: S2–S7
Steps:
1. Consumer audit: all 7 consumers (cmd + 5 + ctrlshft) have zero vendored engine files.
2. Live workflow test: trigger one agent per consumer; confirm outputs match pre-migration baselines.
3. Drift test: simulate a hub main push; confirm SHA-drift opens review PRs (not file-diff re-vendors).
4. Pin test: pin one consumer to a fixed SHA; confirm it doesn't pick up newer hub main.
5. Portfolio review: hub README stands alone as documented senior-engineered artifact.
6. Mark ADR-008 fully implemented; archive this plan.
Acceptance criteria: All green; ADR-008 Accepted; plan archived.
Feedback loops: full QA checklist.

---

## 4. Key Insights

```
Critical Principle: The producer must dogfood its own distribution model.
Why it matters: ctrlshft still vendors the engine it produces — the exact
  drift pattern the hub eliminates. If the producer won't run on the hub,
  the model is unproven and the vendored copy stays alive forever.
How to apply: Migrate ctrlshft to hub stubs (S2), remove shft/engine,
  and let the hub's own dogfood (S3) file engine-PRDs where the engine lives.
Risk if ignored: The vendored engine persists in the producer, drift returns,
  and the hub model is never validated by its own author.
```

```
Critical Principle: Engine-PRDs belong where the engine lives.
Why it matters: The 21 ctrlshft source:architecture-review issues are a mix
  of engine-scoped and non-engine. Bulk-moving them to the hub would drag
  HUD/bridge/context issues into the wrong repo and orphan engine-PRDs until
  the hub dogfoods.
How to apply: Let the hub's own architecture-review pass file engine-PRDs in
  the hub (S3), then close ctrlshft engine-scoped issues as duplicates (S7).
  Non-engine issues stay in ctrlshft.
Risk if ignored: Issue trackers become inconsistent; engine-PRDs get lost
  between repos.
```

```
Critical Principle: Release tooling must exist before retiring the old flow.
Why it matters: update-sandcastle.sh can't be retired until hub/release.sh
  replaces it — otherwise consumers have no way to pin/update the engine.
How to apply: Build release.sh (S4) before retiring the script (S5).
Risk if ignored: Consumers lose the update path; drift workflow has no
  release mechanism.
```

---

## 5. Dependency Graph

```
S1 (merge cmd + validate pilot) [HITL]
 ├─▶ S2 (migrate ctrlshft) [HITL]
 │    └─▶ S3 (hub self-dogfood) [AFK]
 │         └─▶ S7 (issue cleanup) [HITL]
 ├─▶ S4 (build release.sh) [AFK]  ← parallel-safe
 │    └─▶ S5 (retire update-sandcastle.sh) [AFK]
 └─▶ S6 (rollout 5 consumers) [AFK]
      └─▶ S8 (final QA + docs) [HITL]
```

Parallel-safe:
- **S4** (release.sh) can run immediately — no dependency on the pilot.
- **S2** blocks S3 (hub dogfood needs the consumer pattern proven).
- **S3** blocks S7 (hub must file engine-PRDs before closing ctrlshft dups).
- **S6** blocks S5 (all consumers migrated before retiring the script).
- **S8** is the final gate.

Critical path: `S1 → S2 → S3 → S7` and `S4 → S5` and `S6 → S8`.

---

## 6. QA Plan (final HITL slice)

After S8:

1. **Consumer audit:** for each of the 7 consumers (cmd, ctrlshft, launch, aligned, PUSH, riseawake.com, claude-code-copilot), verify `git ls-files .sandcastle` contains only `hub-version.json` (+ any consumer-owned prompt overrides); no engine lib/workflows/scripts tracked.
2. **Live workflow test:** trigger `workflow_dispatch` on at least one agent per consumer and confirm the run output, labels, and any issue/PR creation match pre-migration baselines.
3. **Drift test:** simulate a hub `main` push (add a benign commit), confirm SHA-drift workflows open review PRs (not file-diff re-vendors) within the next scheduled window.
4. **Pin test:** pin one consumer's `hub-version.json` to a fixed SHA, confirm it does NOT pick up the newer hub main.
5. **Recovery test:** revert one consumer to `@main`, confirm it picks up hub latest.
6. **Hub dogfood test:** confirm the hub's own architecture-review + repo-hygiene file engine-PRDs in the hub.
7. **Portfolio review:** open the public hub README — does it stand alone as a documented, senior-engineered artifact for recruiters/clients?

All green → mark ADR-008 fully implemented, archive this plan.

---