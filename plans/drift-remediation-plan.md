# Architecture Plan — Drift Remediation, Complete Sync & Allowlist Modernization

**Status:** Proposed — awaiting approval
**Date:** 2026-08-20
**Derived from:** `bin/check-public-drift.sh` output, `seams/public-pullback.md`, `seams/vendor-sandcastle.md`, `WORKSPACE_INVARIANTS.md`
**Executed by:** AFK agents (shft) for AFK slices; HITL for the reset slices

---

## 1. Context

The repo sync work is complete (all repos clean + pushed, hub↔producer templates
14/14 in sync, PR #335 merged and local main fast-forwarded). What remains is
**drift between public and dotfiles on the allowlisted product paths** plus two
**dead engine trees left behind by the hub migration**.

Current drift (from `bin/check-public-drift.sh`):

| Path | Nature | Direction |
| --- | --- | --- |
| `shft/engine/**` | dotfiles still tracks the old engine; public DELETED it (hub owns it now) | dotfiles has leftover — **cleanup** |
| `.sandcastle/engine/**` | same legacy vendored engine in dotfiles | **cleanup** |
| `.sandcastle/scripts/**` | same legacy vendored scripts in dotfiles | **cleanup** |
| `shft/templates/scripts/check-workflow-enabled.sh` | public has new hub-model script | **pullback** to dotfiles |
| `bin/pipeline-label-data.sh` | public has +11 lines (label map) | **pullback** |
| `test/hooks/` | public has 2 new tests + extended helpers | **pullback** |

The drift allowlist itself is stale: it still lists `shft/engine`,
`.sandcastle/engine`, `.sandcastle/scripts` as *shared product paths*, but the
hub migration removed them from the public producer — so the drift check
reports phantom missing files forever. Without fixing both the leftover trees
AND the allowlist, `check-public-drift.sh` stays red on dead paths.

---

## 2. Design Decisions

| Decision | Choice | Rationale |
| --- | --- | --- |
| Engine leftover (`shft/engine`) | **Delete from dotfiles tracking** (it was a mirrored copy; hub owns the engine) | Public already deleted it; dotfiles must match to make drift green |
| `.sandcastle/engine` + `.sandcastle/scripts` | **Delete from dotfiles** (legacy vendored install) | Same — hub owns; consumers hold stubs + hub-version, not the engine |
| New hub scripts + label map + hook tests | **Pull back** (Direction A: `git checkout public/main -- <paths>`) | These are real product increment test/harness bits produced in public |
| Drift allowlist | **Remove** `shft/engine`, `.sandcastle/engine`, `.sandcastle/scripts` (paths gone from product) | Stale allowlist entries create permanent phantom drift reporting |
| Add to allowlist? | Keep `shft/templates/scripts`, `test/hooks`, `bin/pipeline-label-data.sh` | They're still shared product paths with real drift |
| `check-workflow-enabled.sh` | Pull back to dotfiles `shft/templates/scripts/` | The hub stub contract requires it in the producer install |
| `test-helpers.sh` | Pull back public's extended version (2 new JSON builders) | Required by the 2 new hook test files |
| Cleanup safety | Keep `.sandcastle/CODING_STANDARDS.md`, `prompts/`, `templates/`, `labels.json`, `run.ts` — those are consumer install artifacts, NOT the engine | Differentiate "engine + scripts" (delete) from "consumer artifacts" (keep) |

---

## 3. Vertical Slices

> Each slice is independently shippable and wires end-to-end.

---

### ☐ SYNC-1: Clean up the dead engine paths (dotfiles)
Type: HITL (returns to working tree)
Size: M
Blocked by: none
Steps:
1. `git -C testdotfiles rm -r shft/engine` — removes the tracked mirrored engine.
2. `git -C dotfiles rm -r .sandcastle/engine .sandcastle/scripts` — legacy vendered install.
   (Do NOT touch `.sandcastle/{CODING_STANDARDS.md,hooks,prompts,templates,labels.json,run.ts}` — consumer artifacts stay.)
3. Run `bin/check-public-drift.sh` — those three entries should now be gone (paths no longer exist on either side).
Acceptance: `git ls-files` for `shft/engine`, `.sandcastle/engine`, `.sandcastle/scripts` empty; drift list no longer names them.
Feedback: `bash bin/check-public-drift.sh` post-delete → no those entries.

---

### ☐ SYNC-2: Pullback the real product drift — 4 paths
Type: HITL
Size: M
Blocked by: none (independent of SYNC-1)
Steps:
1. On a scratch branch from `dev`: `git switch -c san/sync/pull-<area>`.
2. Pullback the three real product areas per `seams/public-pullback.md`:
   - `git checkout public/main -- shft/templates/scripts/check-workflow-enabled.sh`
   - `git checkout public/main -- bin/pipeline-label-data.sh`
   - `git checkout public/main -- test/hooks/` (pulls the 3 files: 2 new tests + merged helpers)
3. Run the hook suite: `bash test/hooks/run-hook-tests.sh` (runner auto-discovers `test-*.sh`).
4. Run `bash test/sandcastle-smoke-coverage.sh` + `bash test/prime-smoke.sh` (regression).
5. Commit `sync(pullback): hook tests + pipeline-label-data + check-workflow-enabled`.
Acceptance: 3 new files present in dotfiles; hook runner green; the two smoke suites green.
Feedback: `bash test/hooks/run-hook-tests.sh`; `bash test/sandcastle-smoke-coverage.sh`; `bash test/prime-smoke.sh`.

---

### ☐ SYNC-3: Update the drift allowlist
Type: AFK
Size: S
Blocked by: SYNC-1 (list edit based on deletion outcome)
Steps:
1. In `bin/check-public-drift.sh` (PRODUCT_PATHS array) remove the three
   engine paths that the hub migration deleted from the product:
   - `"shft/engine"`
   - `".sandcastle/engine"`
   - `".sandcastle/scripts"`
2. Keep the still-shared product paths:
   `bridge`, `shft/templates/scripts`, `bin/pipeline-label-data.sh`, `test/hooks`.
3. Re-run `bin/check-public-drift.sh` — engine paths no longer flagged.
Acceptance: `check-public-drift.sh` exits 0 (no drift); no phantom engine-path
entries remain in the product allowlist.
Feedback: `bash bin/check-public-drift.sh` (expect "No drift").

---

### ☐ SYNC-4: Verify end-to-end template & hub parity
Type: AFK
Size: S
Blocked by: SYNC-1..3
Steps:
1. `bash bin/sync-hub-templates.sh --check` — 14/14 in sync.
2. `bash test/prime-smoke.sh` — the prime command still works on the cleansed tree.
3. `bash test/init-sandcastle-proxy-canary.sh` — init still renders stubs (after engine removal).
Acceptance: all 3 gates green on a tree with no vendored engine.

---

## 4. Key Insights

Critical Principle: The drift allowlist must reflect the model, not the history.
Why it matters: paths removed from the product (engine → hub) leave allowlisted → permanent phantom drift red on every run.
How to apply: after deleting a shared path from one side, remove it from the allowlist, not just the filesystem.
Risk if ignored: drift-check permanently reports dead paths; no one trusts the green signal.

Critical Principle: Distinguish "engine was deleted" from "consumer artifacts were deleted".
Why it matters: `shft/engine` + `.sandcastle/engine`/`scripts` are engine installs the hub now owns; `CODING_STANDARDS.md`, `prompts/`, `labels.json`, `run.ts` are consumer artifacts that stay.
How to apply: delete only the engine dirs matched by the migration; keep the consumer install shell.
Risk if ignored: removing consumer artifacts breaks init-sandcastle.

---

## 5. Dependency Graph

```
SYNC-1 (delete dead engine dirs) ──► SYNC-3 (fix allowlist)
SYNC-2 (pullback real product)  ──► SYNC-4 (verify end-to-end)
```

- SYNC-1, SYNC-2 independent (both touch dotfiles; safe parallel on a scratch branch)
- SYNC-1 → SYNC-3 (allowlist reflects deletion)
- SYNC-1+2+3 → SYNC-4 (final gate)
- Order: [SYNC-1 ∥ SYNC-2] → SYNC-3 → SYNC-4

---

## 6. QA Plan

The final QA slice (HITL):
1. `bash bin/check-public-drift.sh` returns "No drift" (both the deleted paths gone AND the real pullback applied).
2. `shft/engine`, `.sandcastle/engine`/`.sandcastle/scripts` absent from `git ls-files` in both repos.
3. `bash test/hooks/run-hook-tests.sh`, `bash test/sandcastle-smoke-coverage.sh`, `bash test/prime-smoke.sh`, `bash test/init-sandcastle-proxy-canary.sh` all green.
4. `bash bin/sync-hub-templates.sh --check` reports 14/14 in sync.
5. Public and dotfiles diff the 5 pulled-back paths 1:1.
6. No `shft/engine`, `.sandcastle/engine`, `.sandcastle/scripts` anywhere in `git ls-files` of either repo.