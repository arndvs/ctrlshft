# Implementation Plan: Dual-Method Skill System (Claude `/commands` + Copilot auto-invocation)

## 1. Context

Skills in `~/dotfiles/skills/` are the single source of truth for 55 workflows, deployed to both
Claude Code (`~/.claude/skills` symlink) and Copilot (`~/.copilot/skills` materialized copy via
`bootstrap.sh`). The two harnesses invoke them completely differently:

- **Copilot** auto-invokes skills by their `description` field — each skill is a first-class tool with
  progressive loading (~100 tokens discovery), so keyword-rich descriptions reliably trigger.
- **Claude Code** exposes ONE generic `Skill` tool + a ~125K-char text catalog (~31K tokens). The model
  must read the whole catalog and self-select — small/flash models bury this and skip skill invocation
  entirely. Only 17 of 55 skills have `/command` dispatchers that bypass the model's judgment.

The fix: **deterministic command coverage for every skill in Claude** (command dispatchers generated
from skill metadata) + **pruned, keyword-rich skill catalog for Copilot** (description-driven auto-invocation)
+ **explicit routing table** in always-loaded instructions for both. One skill definition, two invocation paths.

## 2. Design Decisions

| Decision | Choice |
| -------- | ------ |
| Skill source of truth | Single `~/dotfiles/skills/*/SKILL.md` (unchanged) |
| Claude invocation | Generated `/command` dispatcher per skill (deterministic, bypasses model judgment) |
| Copilot invocation | Auto-invocation by `description` (already works) — no command needed |
| Command generator | New `bin/gen-commands.sh` — idempotent, regenerates all command dispatchers from skill metadata |
| Command lifecycle | Generated commands are checked-in (not ephemeral) — deterministic diff, PR reviewable |
| Command template | Match existing `commands/*.md` pattern (load skill + `$ARGUMENTS` passthrough) |
| Copilot frontmatter | Add `disable-model-invocation` opt-out to skills that should NOT auto-trigger; default stays auto |
| Catalog pruning | Move rarely-used skills to `skills/_local/` (gitignored, already supported by `materialize_copilot_skills`) — NOT deleted |
| Routing table | Add "Skill Routing" section to `CLAUDE.base.md` (source for both `CLAUDE.md` + `copilot-instructions.md`) |
| Validation | Extend `bin/validate-skills.sh` to check command coverage + new frontmatter fields |
| Conflicts | Command filename collisions (e.g. `review` → `code-review`) resolved by explicit allowlist table in generator |

## 3. Vertical Slices

---

☐ **Slice 1: Command generator `bin/gen-commands.sh`**
Type: AFK
Size: M
Blocked by: none
Steps:
1. Write `bin/gen-commands.sh` with `set -euo pipefail` (per repo convention)
2. Iterate `~/dotfiles/skills/*/SKILL.md` (skip `_local/`, `_vendor/`, dot-dirs)
3. For each skill lacking a command, generate `~/dotfiles/commands/<skill>.md`:
   ```
   Load the <skill> skill from ~/dotfiles/skills/<skill>/SKILL.md. Execute the workflow.

   $ARGUMENTS
   ```
4. Include a collision-resolution map: skill names that map to a different command filename
   (e.g. `code-review` → `review.md`, `atomic-commits` → `commit.md`/`ship.md`, `do-work` → `work.md`,
   `session-close` → `check.md`, `architect` → `plan.md`, `pr-preflight` → `preflight.md`,
   `tdd` → `test.md`, `explore` → `explore.md`, `codebase-audit` → `audit.md`, `review-pr-copilot` → `address-review.md`)
5. Preserve existing hand-written command bodies (only generate for missing skills — idempotent)
6. Add `--check` mode that fails if any skill lacks a command (for CI)
7. Wire into `bin/bootstrap.sh` (step 6, after commands symlink) and optionally `bin/_lib.sh`

Acceptance criteria:
- `bash bin/gen-commands.sh` creates one `.md` per skill lacking a command; re-run is a no-op
- `bash bin/gen-commands.sh --check` exits 0 after generation, non-zero if any skill uncovered
- Output format matches existing command files exactly
- `validate-skills.sh` still passes after generation

Feedback loops: `bash test/skills.sh`, `bash bin/gen-commands.sh --check`, shellcheck `bin/gen-commands.sh`

---

☐ **Slice 2: Frontmatter audit + `disable-model-invocation` support**
Type: AFK
Size: M
Blocked by: none
Steps:
1. Review all 55 skill frontmatters for Copilot compatibility (name matches dir, description quoted with triggers)
2. Add `disable-model-invocation: true` to skills that should NOT auto-trigger in Copilot (e.g. superpowers-style meta-skills, `compliance-audit` auto-invoke skill, session-close)
3. Add `argument-hint` to skills commonly invoked via `/` in Copilot (optional polish)
4. Extend `bin/validate-skills.sh` to accept and validate the new fields (no error if absent — additive)
5. Regenerate `~/.copilot/skills` via `bash bin/bootstrap.sh` (or `materialize_copilot_skills` directly)

Acceptance criteria:
- `bin/validate-skills.sh` passes with new frontmatter fields
- `~/.copilot/skills/*/SKILL.md` includes the new fields after materialization
- No skill has both `disable-model-invocation: true` AND `user-invocable: false` unintentionally

Feedback loops: `bash test/skills.sh`, `bash test/copilot-skills-materialize.sh`

---

☐ **Slice 3: Catalog pruning — move rare skills to `_local/`**
Type: HITL
Size: L
Blocked by: none
Steps:
1. Inventory all 55 skills with usage metadata (git log frequency, session log load counts)
2. Categorize: core (keep shared), niche/rare (move to `_local/`), stale (flag for review)
3. `git mv` shared → `skills/_local/<skill>/` (preserve history)
4. Update `materialize_copilot_skills` if needed (already handles `_local/`)
5. Confirm bootstrap reports correct `shared vs local` counts
6. Document the triage in `commands/README.md`

Acceptance criteria:
- `_local/` populated with moved skills; shared catalog reduced to a scannable size (~15-20)
- `bash bin/bootstrap.sh` reports matching shared/local counts
- Copilot `~/.copilot/skills` reflects the pruned set
- All moved skills still reachable via `/command` (generator in Slice 1 covers `_local/` too)

Feedback loops: `bash test/skills.sh`, `bash test/copilot-skills-materialize.sh`, `bash bin/bootstrap.sh`

---

☐ **Slice 4: Skill routing table in `CLAUDE.base.md`**
Type: HITL
Size: S
Blocked by: Slice 3 (final skill set)
Steps:
1. Add a `## Skill Routing` section to `CLAUDE.base.md` (before "Always-Loaded Instructions")
2. Table: trigger phrases → command to run / skill to load (for both harnesses)
3. Update `commands/README.md` command inventory with the new generated commands
4. Re-run `bash bin/bootstrap.sh` to regenerate `CLAUDE.md` + `~/.copilot/copilot-instructions.md`
5. Add a note in `global.instructions.md` pointing at the routing table (short)

Acceptance criteria:
- `CLAUDE.base.md` (git-tracked) contains the routing table; `CLAUDE.md` + `copilot-instructions.md` regenerate with it
- Every skill in the shared catalog has a routing row
- `test/copilot-instructions.sh` and `test/claude-instructions.sh` still pass

Feedback loops: `bash bootstrap.sh`, `bash test/copilot-instructions.sh`, `bash test/claude-instructions.sh`

---

☐ **Slice 5: Test coverage for command generation**
Type: AFK
Size: S
Blocked by: Slice 1
Steps:
1. Add `test/gen-commands.sh` — fixtures: a skills tree with covered + uncovered skills + `_local/`
2. Assert: generation creates commands for uncovered, preserves existing, `--check` fails when stale
3. Wire into `test/run-all.sh`
4. Add a `test/command-coverage.sh` that asserts every shared skill has a command (both generated and allowlisted)

Acceptance criteria:
- New tests pass; `test/run-all.sh` green
- Coverage test fails if a new shared skill is added without a command

Feedback loops: `bash test/run-all.sh`

---

☐ **Slice 6: QA — dual-harness end-to-end verification**
Type: HITL
Size: S
Blocked by: Slices 1-5
Steps:
1. Claude: type `/audit` → confirm `codebase-audit` skill loads and runs
2. Claude: type `/work` → confirm `do-work` skill loads (regression)
3. Claude: type a bare "audit this codebase" → confirm the model now loads the skill (routing table effect)
4. Copilot: open a chat, say "audit this" → confirm skill auto-invokes via description
5. Verify `~/.claude/skills/`, `~/.copilot/skills/`, `~/.claude/commands/` symlinks/materialization all correct
6. Confirm context bloat reduced (Claude session starts with smaller skill catalog)

Acceptance criteria:
- Both harnesses load the same `codebase-audit` skill from the same source
- Claude CLI reliably loads skills when asked (no more "ignored" behavior)
- Copilot auto-invocation still fires; no regressions in either harness

## 4. Key Insights

```
Critical Principle: Skills are the implementation; commands are the deterministic dispatch layer.
Why it matters: Claude's generic Skill tool is unreliable for small/flash models because it requires
  reading a 31K-token catalog and self-selecting. A generated /command bypasses the model's judgment
  entirely — the user typing /audit guarantees the skill loads.
How to apply: Generate commands from skill metadata (name + description), never hand-maintain them.
Risk if ignored: Skill usage remains lottery-based — some sessions load, most don't.
```

```
Critical Principle: Copilot already auto-invokes by description; the bottleneck is catalog size, not mechanism.
Why it matters: With 55 skills, the discovery surface (description scan) is diluted. Progressive loading
  means keyword-rich descriptions win. Pruning to the frequently-used set makes auto-invocation reliable.
How to apply: Move rare skills to skills/_local/ (gitignored) — they stay reachable via /command but
  don't pollute Copilot's discovery surface.
Risk if ignored: Copilot picks the wrong skill or none; context bloat on every session start.
```

```
Critical Principle: Single source of truth, two consumer targets.
Why it matters: CLAUDE.base.md generates both CLAUDE.md (Claude) and copilot-instructions.md (Copilot).
  Skills/ generate ~/.claude/skills (symlink) + ~/.copilot/skills (materialized). Never edit consumers.
How to apply: All changes land in dotfiles/ source; bootstrap.sh propagates.
Risk if ignored: Drift between harnesses; edited consumer files silently overwritten.
```

## 5. Dependency Graph

```
Slice 1 (gen-commands.sh) ────────┐
                                 ├──▶ Slice 5 (test coverage)
Slice 2 (frontmatter audit) ──────┤
                                 ├──▶ Slice 6 (QA)
Slice 3 (catalog pruning) ────────┴──▶ Slice 4 (routing table)
                                          │
                                          └──▶ Slice 6 (QA)
```

Parallel-safe:
- Slices 1, 2, 3 can run in parallel (independent file sets)
- Slice 4 blocked by Slice 3 (routing table needs final skill list)
- Slice 5 blocked by Slice 1
- Slice 6 blocked by all

Ordering recommendation: **Slice 1 → Slice 3 → Slice 2** (generator first = immediate deterministic path,
then pruning = context relief, then frontmatter polish), with Slice 4 after 3. All are AFK except Slice 3,
4, and 6 (taste/verification decisions).

## 6. QA Plan

After all slices complete, the human verifies:

1. **Claude determinism**: `/audit`, `/work`, and 2-3 other generated commands all load their skills
   (previously only 17 worked; now all should).
2. **Claude natural language**: "audit this codebase" without `/` loads the skill (routing table working).
3. **Copilot auto-invoke**: "audit this" in Copilot Chat loads the skill without slash.
4. **Same source**: both load from `~/dotfiles/skills/codebase-audit/SKILL.md` — edit once, both update.
5. **Context bloat check**: a fresh Claude session shows a much smaller skill catalog (~31K tokens → ~10K).
6. **No regressions**: `test/run-all.sh` fully green; `validate-skills.sh` passes; bootstrap completes clean.

Rollback: `git revert` the command generator + routing table commits; move `_local/` skills back with `git mv`.