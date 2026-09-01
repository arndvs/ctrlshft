# Architecture Plan — Public Docs Cleanup & Workspace Organization

**Status:** Proposed — awaiting approval
**Date:** 2026-08-20
**Derived from:** Codebase audit (2026-08-20), `docs/sandcastle-hub-architecture.md`, `docs/adr/ADR-008-ctrlshft-hub.md`, `plans/README.md`, `WORKSPACE_INVARIANTS.md`
**Executed by:** AFK agents (shft) for AFK slices; HITL for taste decisions

---

## 1. Context

The public repo's docs have drifted into a state that misrepresents the product.
The hub migration removed the vendored engine, but **~1,300 lines of documentation
still describe the old model** as current: `CONTEXT.md` claims the repo "intentionally
vendors" the dead engine, `shft/README.md` documents `update-sandcastle.sh` alone as
the flow, and `docs/ARCHITECTURE.md`'s ADR index stops at ADR-004 while 8 exist.
Five completed plans carry "Proposed — awaiting approval" headers despite their
entire scope being shipped, in direct violation of `plans/README.md`'s own
"Archive or delete after work completes" rule. The `working/` lane convention
(`active`/`refs`/`research`) is broken by `working/saas-starter-lift-plan.md`
sitting loose at root, and Docs Haves duplicated stub files. The result is a
public-facing surface that misleads readers and burns agent context re-deriving
the true structure.

## 2. Design Decisions

| Decision | Choice | Rationale |
| --- | --- | --- |
| `plans/` lifecycle | **Move all 5 completed plans to `plans/archive/`** (with a status banner), not delete | Git history preserves content; archive keeps it discoverable without pretending it's live |
| `working/` root-file | **`saas-starter-lift-plan.md` → archive** (it's marked Implemented; delete-or-archive) | The lane model says working/ root must be empty except README |
| `working/active/sandcastle-loose-ends.md` | **Archive** (PR #326 merged; all slices done) | Active file describes completed work |
| `CONTEXT.md` stale claims | **Rewrite lines 25-28** to hub model (SHA-lock + stubs, no vendoring) | Factual error in the canonical context doc is the worst kind of drift |
| `shft/README.md` | **Rewrite** vendored-model section → hub-model description | Documents a removed model as live guidance |
| `docs/ARCHITECTURE.md` ADR index | **Add ADR-005..008 rows** | Canonical doc is factually incomplete |
| `docs/sandcastle-hub-architecture.md` | **Archive** (superseded by ADR-008) | Design draft duplicates the accepted decision |
| `docs/research/sandcastle-extraction.md` | **Archive** (documents the removed vendored model) | Dead doc for dead model |
| `docs/qa/dogfood-baseline.md` stub | **Delete** | 3-line stub pointing to canonical file; no reader value |
| `README.md` redundancy | **Trim to a single install section** + fix file tree | 67KB with 33 bootstrap mentions is unreadable |
| Cross-repo doc parity | **Public is canonical; dotfiles mirrors** (per REPO_TOPOLOGY) | Fix divergence only in public; dotfiles pulls back after |
| `docs/audits/readme-site-deep-audit.md` | **Keep but add "historical — resolved" banner** | Dated assessment; conversion to ref not a delete |
| `docs/research/observability-benchmarking.md` | **Update status from roadmap → shipped** | Bandwidth: shipped since audit |

---

## 3. Vertical Slices

### ☐ DOCS-1: Archive completed plans
Type: AFK
Size: S
Blocked by: none
Steps:
1. Create `plans/archive/`.
2. Move the 5 `plans/*.plan.md` files: `ctrlshft-hub-plan.md`, `ctrlshft-hub-dogfood-plan.md`, `hub-model-cleanup-plan.md`, `workspace-prime-plan.md`, `drift-remediation-plan.md` → `plans/archive/`.
3. Prepend each with an `> **Archived** — implemented; see git history for the shipping commits.` banner.
4. Update `plans/README.md` to list the archive dir and its link.
Acceptance: `plans/` shows only README + `issues/` + `archive/`; archive dir has banner. Feedback: `ls plans/`.

### ☐ CLEAN-2: Clean `working/` lanes
Type: AFK
Size: S
Blocked by: none
Steps:
1. `git mv working/saas-starter-lift-plan.md plans/archive/` (implemented doc, one way).
2. `git mv working/active/sandcastle-loose-ends.md plans/archive/` (PR merged).
3. Verify `working/` root now only has README; `active/` only README.
Acceptance: `ls working/` → README.md `ls working/active/` → README.md. Feedback: `ls working/ working/active/`.

### ☐ FIX-3: Correct the factual docs
Type: HITL
Size: M
Blocked by: none
Steps:
1. `CONTEXT.md:25-28` (repo root) → rewrite to SHA-lock hub model:
   - Replace the "intentionally vendored from shft/" claim with "holds a `hub-version.json` SHA-lock; engine runs from `arndvs/ctrlshft-hub` via the `agent-run` action."
   - Drop the `update-sandcastle --dry-run` drift line (deprecated flow).
2. `docs/ARCHITECTURE.md` ADR table → add rows for ADR-005..008 (names from `docs/adr/`).
3. `shft/README.md` vendored section → replace `update-sandcastle`/vendored-engine description with the hub-model `uses:` + SHA-lock flow.
Acceptance: `grep -riE "vendored|update-sandcastle|intentionally vendored" CONTEXT.md shft/README.md docs/ARCHITECTURE.md` → no stale claims (or only accurate "deprecated" notes). Feedback: the grep.

### ☐ DEAD-4: Remove dead stub + superseded docs
Type: AFK
Size: S
Blocked by: none
Steps:
1. `git rm docs/qa/dogfood-baseline.md` (3-line stub).
2. `git mv docs/sandcastle-hub-architecture.md docs/archive/` (superseded by ADR-008).
3. `git mv docs/research/sandcastle-extraction.md docs/archive/` (vendored model doc).
4. `git mv docs/audits/readme-site-deep-audit.md docs/archive/` (resolved audit).
Acceptance: `ls docs/qa/` empty (dir removable); archive holds the 3 moved docs. Feedback: `find docs -name "*.md" | wc -l`.

### ☐ TRIM-5: Trim README redundancy
Type: HITL
Size: M (judgment on what to cut)
Blocked by: FIX-3 (README's stale sections reference the removed model; fix doc first)
Steps:
1. Identify the 3 duplicated `<details>` install blocks; keep ONE canonical bootstrap walkthrough.
2. Fix the file-tree section to reflect `plans/`, `docs/qa/`, hub-version `.sandcastle/`, not the old vendored tree.
3. Remove sections that refer to the dead `update-sandcastle` flow (already replaced in FIX-3 target doc); link to the canonical ADR instead.
Acceptance: `wc -l README.md` < ~800; install walkthrough appears once; no "vendored engine" prose. Feedback: `wc -l README.md`.

---

## 4. Key Insights

Critical Principle: **Docs are either live or archived; a "status" header that lies is worse than no doc.
Why it matters: readers (humans + agents) trust headers. 5 plans with `Status: Proposed` whose scope is merged is active misinformation.
How to apply: any doc whose owning work has merged gets the Archive banner + a one-line "implemented in <sha>" note, OR deleted.
Risk if ignored: agents re-read dead plans and try to re-do shipped work (exactly the drift we already fought).

Critical Principle: the public repo is the canonical doc surface; dotfiles mirrors.
Why it matters: the two docs trees have already diverged (ADR-007/008 only in public; `archive/` etc. only in dotfiles).
How to apply: make all doc edits in public only, then pull back to dotfiles; update sync allowlist for the doc paths.

---

## 5. Dependency Graph

```
CLEAN-2 (working/ lanes)  ∥  DEAD-4 (remove stubs/superseded)
FIX-3 (factual corrections) → TRIM-5 (README trim)
CLEAN-1 (archive plans)  //  (all independent)
```

Order: `[CLEAN-1 ∥ CLEAN-2 ∥ DEAD-4] → FIX-3 → TRIM-5`.
- CLEAN-1/2/DEAD-4 parallel-safe (different dirs).
- FIX-3 independent but logically precedes TRIM-5 (README references it).
- TRIM-5 last (needs the corrected facts to trim accurately).

## 6. QA Plan

The final QA slice (HIT) verifies:
1. `plans/` = README + archive/ + issues/; archive files all have "Archived" banner.
2. `working/` = README only at root; `working/active/` = README only.
3. `CONTEXT.md`, `shft/README.md`, `docs/ARCHITECTURE.md`: no old-model claims; grep clean.
4. `docs/` no longer has `sandcastle-hub-architecture.md`, `research/sandcastle-extraction.md`, `readme-site-deep-audit.md` — they're in `docs/archive/`.
5. `README.md` converges to < 800 lines, single install block, accurate tree.
6. After commit/push, pull back the same cleanup to dotfiles so both trees align.