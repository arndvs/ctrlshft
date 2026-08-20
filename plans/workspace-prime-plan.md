# Architecture Plan — Workspace Prime & Ownership Scaffold

**Status:** Proposed — awaiting approval
**Date:** 2026-08-20
**Derived from:** TAC-1 `prime.md` draft, `working/refs/tac/examples/` (`WORKSPACE_INVARIANTS.md`, `public-pullback.md`), `REPO_TOPOLOGY.md`, `docs/sandcastle-hub-architecture.md`
**Executed by:** AFK agents (shft) for AFK slices; human for HITL slices

---

## 1. Context

This session repeatedly burned context re-discovering multi-root workspace
topology: which repo owns which path, when a change crosses a repo seam, which
secrets/working dirs are private-only, and when a public push needs a guard
token. The guards already exist (`check-public-drift.sh`,
`validate-remotes.sh`, `validate-public-promotion.sh`), and context detection
exists (`detect-context.sh` → `ACTIVE_CONTEXTS`) — but they answer *"what kind of
project is this?"*, not *"which root owns the path I'm about to write, and which
procedure applies?"*

TAC-1's `prime.md` draft + the two seam/invariant docs solve exactly this: a
**priming step** that, given a task scope, classifies which roots it touches,
reports dirty state + drift, and produces an ownership verdict table before any
code is written. This plan turns the drafts into a working `ctrl prime` command,
per-root `AGENT_PRIME.md` files, seam docs, and a skill wrapper — built on the
existing invariant scaffolding instead of inventing a parallel system.

## 2. Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Prime executable home | `bin/prime.sh` in **dotfiles**, dispatched as `ctrl prime "<scope>"` | `ctrl` is the existing CLI surface; `bin/` holds all the guard helpers it shells out to |
| Verdict output format | **Plain-text table** to stdout (path → owning root → branch 1/2/3 → procedure) | Machine-parseable, agent-readable, terminal-friendly. No JSON ceremony. |
| Exit policy | Exit **non-zero on branch 3** (unclassified path); exit 0 with a verdict for 1/2 | Branch 3 must stop the agent from guessing — that's the core value. |
| Per-root prime docs | **`AGENTS.md`** at each root (not a new file name) | It's the established agent-instruction convention; agents auto-read `AGENTS.md` on entry. |
| Canonical invariants | **`dotfiles/WORKSPACE_INVARIANTS.md`** — single source; other repos reference it | Avoids the drift problem the draft's "CONTESTED" entries point at. |
| Seam docs | `dotfiles/seams/{public-pullback,vendor-sandcastle,anythingelse}.md` | Edge procedures for cross-root operations; referenced, not inlined into invariants. |
| Wiring | **`ctrl prime`** + **skill `workspace-prime`** + hooks into `do-work`/`architect` skills | Command is the engine; skill makes agents *use it* automatically on multi-root work. |
| Conflicts with existing guards | **Reuse, not replace.** `prime` shells to `check-public-drift.sh`, `validate-remotes.sh` | No duplicated logic; invariants doc references the existing binaries. |
| CONESTED entries (`.sandcastle/config`, installed `agent-*.yml`) | **Resolve as "host-managed consumer assets"** — owner is the *producer* via templates; install-time copy is host-managed | This session's S1-S3 made this concrete: templates are product (owner=ctrlshft/hub), installed copies are host-managed. |

---

## 3. Vertical Slices

> Each slice is independently shippable and wires end-to-end.

---

### ☐ WS1: Publish canonical invariants — `WORKSPACE_INVARIANTS.md`
Type: HITL (taste — resolving the CONTESTED entries)
Size: S
Blocked by: none
Steps:
1. Promote `working/refs/tac/examples/WORKSPACE_INVARIANTS.md` → `dotfiles/WORKSPACE_INVARIANTS.md`
   (canonical copy; the /refs copy becomes a stub pointer).
2. Resolve the two CONTESTED rows:
   - `.sandcastle/config` + installed `.github/workflows/agent-*.yml` →
     **branch 1** (owner = the producer that defines templates). Remove the
     "contested" markers.
3. Add one row per guard that already exists (`check-public-drift.sh`,
   `validate-remotes.sh`, `validate-public-promotion.sh`,
   `preflight-public-promotion.sh`) — the doc becomes the *index* of guards.
4. Update `REPO_TOPOLOGY.md` cross-references to link the invariants doc (canonical copy stays there, not duplicated).
Acceptance: `dotfiles/WORKSPACE_INVARIANTS.md` exists, ≤2 pages, CONTESTED rows resolved, guards indexed.
Feedback loops: does it still fit on one screen? Read once for internal consistency.

---

### ☐ S2: Ship the seam docs — `seams/`
Type: HITL (edge cases need judgment)
Size: S
Blocked by: none (S1 only improves, does not block)
Steps:
1. `dotfiles/seams/public-pullback.md` — from `examples/public-pullback.md`:
   Direction A (pullback: `git fetch public main` + checkout paths, exclusions:
   `.github/workflows/*.yml` etc.) vs Direction B (promotion: guarded, `--range`
   + preflight, never direct `dev→main`).
2. `dotfiles/seams/vendor-sandcastle.md` — hub→consumer copy procedure:
   one-way, copy `templates/workflows/` to producer, run parity check with
   `bin/sync-hub-templates.sh`. (This session's S1-S3 distilled exactly this.)
3. `dotfiles/seams/ownership-test.md` — the unclassified-path decision:
   branch 1 (exists in ctrlshft → owner=public, edit there), branch 2 (private-only
   list → dotfiles), branch 3 (neither → STOP ask).
Acceptance: three files under `seams/`, each ≤1 page, no contradiction with
`WORKSPACE_INVARIANTS.md`.

---

### ☐ S3: Build the command — `bin/prime.sh` + `ctrl prime`
Type: HITL (writes the engine; needs human review of the verdict logic)
Size: M
Blocked by: S1 (needs the canonical invariants to reference)
Steps:
1. `bin/prime.sh`:
   - args: scope string (or read from `$1`).
   - Load `WORKSPACE_INVARIANTS.md` section pointers (root table, private-only,
     ownership test) — by cat'ing them, not by including.
   - Classify: asked scope → which roots (default: fewest, refuse over-scope).
     Cross-seam iff root names appear on >1 line → print seam file to read.
   - For each root: `git rev-parse --abbrev-ref HEAD`, `git status --short`.
   - Run `bin/check-public-drift.sh` and state "drift = expected state unless
     this task touches the drifted path".
   - Emit ownership verdict table (path → root → branch 1/2/3 → direct or seam).
   - Exit 1 on branch 3 rows, with instruction: "Ask the user which root owns X."
2. Wire into `bin/ctrl` as `prime)` (like `check)` model):
   ```sh
   prime)
       if [[ ! -f "$DOTFILES/bin/prime.sh" ]]; then red "..."; exit 1; fi
       green "ctrl prime"
       bash "$DOTFILES/bin/prime.sh" "$@"
       ;;
   ```
3. Add to the help text: `ctrl prime "<task scope>"  preflight multi-root task`.
Acceptance: `ctrl prime "fix smoke-coverage in ctrlshft"` prints roots + dirty +
drift + verdict table. `ctrl prime "something vague"` exits 1 asking for scope.

Feedback loops:
`bash -n bin/prime.sh`
`bash bin/prime.sh "test smoke-coverage"` → expects branch in ctrlshft
`bash bin/prime.sh "edit dotfiles/secrets/x"` → branch 2 (private)
`bash bin/prime.sh "touch unknown/path"` → exit 1 (branch 3)

---

### ☐ S4: Per-root `AGENTS.md`
Type: HITL (short docs, taste for the "never edit" list)
Size: S
Blocked by: none
Steps:
1. `ctrlshft-public/AGENTS.md`: primary product source. Owns
   `shft/templates/workflows/**`, `test/`, `docs/adr/*`. Resolve via
   `WORKSPACE_INVARIANTS` (public copy of the doc considered canonical). Use
   `bin/validate-public-promotion.sh` before any public push.
2. `sandcastle-hub/AGENTS.md`: vendor source, engine + templates + labels;
   one-way copy out; sees consumer stubs; never edit consumer copies.
3. `claude-code-copilot/AGENTS.md` already exists (consumer runtime) — update
   cross-link to invariants; add "this is runtime, not product" note.
4. `dotfiles/AGENTS.md`: overlay owner, machine-local paths (secrets/
   working/), never promote them.
Acceptance: 4 files exist, each ≤1 page, each cross-lists the canonical
invariants doc path + its own guarding command; the ownership rules in each
match the S1 canonical doc.

Feedback: `ls AGENTS.md` in the 4 roots
Manual spot-check: does each docs file's "never" list agree with
`WORKSPACE_INVARIANTS.md`'s private-only list?

---

### ☐ S5: Skill wrapper — `skills/workspace-prime/SKILL.md`
Type: AFK
Size: S
Blocked by: S3 (the command must exist)
Steps:
1. `skills/workspace-prime/SKILL.md` frontmatter: description matching the trigger
   "prime", "multi-root", "which repo owns", "seam".
2. Body: on multi-root or file-write tasks → run `ctrl prime "<scope>"`; read the
   verdict; if branch 3 → stop and ask; onward with the verdict as context.
3. Register `contexts: [general]` so it's always available; keep it short.
4. Wire hint into the `architect` skill's planning step: "on multi-root, prime
   first to set root ownership before exploring."
Acceptance: `prime` is triggered automatically when an agent is asked a
multi-root question; it loads the verdict in one shot.

Feedback. Test the skill by prompting "which repo owns vs the shaft?" → should
cue prime.

---

### ☐ S6: Feedback gate — add a prime smoke to `test/`
Type: AFK
Size: S
Blocked by: S3, S5
Steps:
1. `test/prime-smoke.sh`:
   - `bash bin/prime.sh "test/sandcastle-smoke-coverage"` → branch 1, exit 0.
   - `bash bin/prime.sh "secrets/.env.prod"` → branch 2, exit 0.
   - `bash bin/prime.sh "nonsense/unknown"` → branch 3, exit 1.
2. Wire into the repo's test suite (e.g. `test/run-all` or the guards list in S1).
Acceptance: `bash test/prime-smoke.sh` exits 0; a regression that breaks the
verdict table exits non-zero.

Feedback. `bash test/prime-smoke.sh`

---

## 4. Key Insights

    Critical Principle: Ownership is not a lookup; it is a decision procedure.
    Why it matters: the same unclassified path can be both "public work not yet
    promoted" and "private content about to leak".
    How to apply: make branch 3 exit non-zero, forcing the agent to stop and ask —
    never guess which side.
    Risk if ignored: accidental leak or wrongful promotion.

    Critical Principle: Reuse existing guards; don't re-implement drift checks.
    Why it matters: the guards are the executable truth — `prime` should shell out
    to `check-public-drift.sh`/`validate-remotes.sh` rather than re-encode them.
    How to apply: the verdict tables reference the script name, not a copy of its
    logic.
    Risk if ignored: two drift truths drift apart (the very failure mode the
    invariants doc warns about).

---

## 5. Dependency Graph

```
S1 (invariants) ────────────┐
                            ├──? S3 (prime command) ──► S5 (skill) ──► S6 (test)
S2 (seams) ─────────────────┘           ▲
S4 (AGENTS per root) ───────┘ (parallel safe)

```

- S1 → S3 (command reads the canonical invariants).
- S2 ∥ S1 (seams are edge docs, can be written in parallel).
- S4 ∥ S1..S3 (per-root docs, no dep on the command).
- S3 → S5 (skill wraps the command).
- S5 → S6 (test guards the whole).
- S1, S2, S4 all parallel first; then S3 → S5 → S6.

Execution order: `[ S1, S2, S4 ] → S3 → S5 → S6`.

---

## 6. QA Plan

The final QA slice (HITL) verifies the implementation:

1. `ctrl prime "fix smoke-coverage in ctrlshft"` → prints a verdict table that
   names ctrlshft as owner of `shft/templates/*` and states branch 1.
2. `ctrl prime "touch anything in dotfiles/secrets"` → branch 2 (private) exit 0.
3. `ctrl prime "touch unknown-foo"` → branch 3 → exit 1 + "ask the agent".
4. An agent at the workspace root, asked "which repo owns the seam
   `shft/engine`?", automatically uses the hidden prime (skill) and reads the
   seam doc — no one tells it to.
5. The invariants doc fits on one screen and the "never" lists all agree
   with the AGENTS.md docs in each root.
6. `test/prime-smoke.sh` passes; a fake branch-3 entry fails it.