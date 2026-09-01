# Implementation Plan v3: Skill Invocation Fix — Measurement-First (revised)

**Supersedes:** `plans/dual-method-skill-system.md` (v1, rejected), `plans/dual-method-skill-system-v2.md` (v2)
**Status:** DRAFT — pending Slice 0 baseline
**Reviewer v2 corrections addressed:** command_permissions claim, intervention ordering (plugins first),
visibility-manifest feasibility, `-p` mode validity, session cost cap, Slice 1 gate, gate-0 threshold.

---

## 1. Context

A Claude Code session typed "is the readme accurate to the codebase repo? codebase audit" and the
`codebase-audit` skill did not load — zero `Skill` tool calls across the whole session, despite the
skill being present in the session `skill_listing` with a matching trigger, and the model being
`deepseek/deepseek-v4-flash-0731` (routed through the local LiteLLM proxy). The failure is
probabilistic: whether a flash-class model honors the skill protocol varies by session.

Prior plans proposed builds (command generator, catalog pruning, routing table) before measuring.
Review found the size claims unverified (~31K tokens was actually ~6-8K), the mechanism claim inferred
(Copilot per-skill tools vs Claude text blob), and no baseline or controlled QA. v2 fixed the structure
(gates, single interventions, remeasure) but introduced a wrong `command_permissions` interpretation and
ordered the interventions to test the smaller half of the bloat first. v3 corrects those inputs.

**Verified facts (this document's plan inputs):**

| Fact | Status | Evidence |
| ---- | ------ | -------- |
| `skill_listing` = 24,679 chars ≈ 6-8K tokens, **93 entries** | ✅ measured | session log attachment |
| …of which ~54 local skills, **~28 plugin skills** (14 superpowers + others), rest built-in | ✅ measured | `find ~/.claude/plugins/cache/ -name SKILL.md` = 28 |
| Model in failed session = `deepseek/deepseek-v4-flash-0731` (proxy) | ✅ measured | 174 messages logged |
| `disable-model-invocation` is CI-deprecated | ✅ verified | `ctrlshft-public/README.md` Integrity checks: "deprecated `disable-model-invocation` flags are absent from `skills/**/SKILL.md`" |
| `.non-discoverable-skills` exists | ✅ verified | at `skills/.non-discoverable-skills` |
| …but it's a **guard** (dirs must NOT have SKILL.md), not a discovery filter | ✅ verified | `test/config-consistency.sh` Invariant 5 |
| `command_permissions = {"allowedTools": []}` | ✅ recorded | session log |
| …but it's a **permission allowlist**, not command discovery | ✅ reviewer + verified | field semantics; `~/.claude/commands/` is symlinked by bootstrap; `commands/audit.md` ships |
| Prior plan "42→55" | ❌ garbled | progressive-disclosure merged at 21 shared skills; 54 now |

**Corrected understanding of the failed session:** `/audit` existed on disk and `~/.claude/commands/`
is symlinked, so the command was *available* to the user. The model was not shown a slash-command
listing in that transcript (no command listing attachment seen), but the user typed natural language —
whether `/audit` was discoverable isn't the failure being investigated. The real question is whether
natural-language triggering works, which Slice 0 measures.

---

## 2. Design Decisions

| Decision | Choice |
| -------- | ------ |
| Build gate | **No build until Slice 0 baseline exists and a decision gate passes** |
| Measurement | Fresh-session invocation rate: same prompt, N sessions, count `Skill` tool calls in logs |
| Session harness | `claude -p` **with hard validity precondition** — verify `skill_listing` + `hook_additional_context` arrive under `-p` before trusting any number |
| Session cost cap | **Kill each session after the first tool call** (or first N tokens) — the outcome (Skill called or not) resolves in the first assistant turn; no full audits run |
| Token accounting | Real `input_tokens` from session logs, not chars/4 |
| Intervention order | **Largest token mover first**: plugin-skill disable (settings change, no code) → local pruning → routing table (if needed) |
| Plugin control | Disable via `enabledPlugins` in `~/.claude/settings.json` (or plugin blocklist) for the measurement run — reversible, no code |
| Visibility manifest | **Dropped as primary** — `~/.claude/skills` is a symlink; a bootstrap-read manifest can't filter what Claude enumerates. Revisit only if intervention shows value AND a native exclusion exists |
| `disable-model-invocation` | **Not used** — CI fails on it (`README.md` Integrity checks); confirmed |
| Command generator | **Deferred to fallback** — only if natural-language invocation can't be fixed by 2-4 |
| Slice 1 gate | **Explicit gate**: if both harnesses share a mechanism, Slices 2-5 are re-scoped. Also: verify Copilot payload capture is even feasible before scheduling |
| Gate 0 threshold | **8/10 is deliberate but documented as a tolerance for an explicit request**; a 20% miss rate is the reported failure class — see decision gate 0 note |

## 3. Vertical Slices

---

☐ **Slice 0: Baseline measurement (BLOCKING — everything waits on this)**
Type: AFK (mechanical) with HITL interpretation
Size: S
Blocked by: none
Steps:
1. Write `bin/measure-skill-invocation.sh`:
   - Spawn N fresh Claude Code sessions with a fixed prompt + cwd
   - **Validity precondition (hard stop if unmet):** each session must contain BOTH `skill_listing`
     and `hook_additional_context` attachments; if `claude -p` omits either, the harness is invalid —
     record and switch capture method (e.g. interactive spawn + auto-command, or log replay)
   - **Cost cap:** terminate each session after the first assistant tool call OR first N output tokens;
     outcome (`Skill` called?) resolves in turn 1
   - Grep session logs for `Skill` tool calls and `attributionSkill` markers; record `input_tokens`
     of the first `llm_request`
2. Prompt: the exact failing prompt — "is the readme accurate to the codebase repo? codebase audit"
   (run in `agentic-nlq` cwd; fallback: any small repo)
3. Run **10 sessions**, record invocation rate (X/10) + per-session token cost
4. Write result to `working/research/skill-invocation-baseline.md`

Acceptance criteria:
- Measured invocation rate (e.g. 3/10), not "sometimes"
- Validity precondition documented — either `-p` passes it or the capture method is swapped
- Per-session token counts recorded; sessions were capped, no full audits ran

Feedback loops: `bash bin/measure-skill-invocation.sh`, manual log inspection

**Decision gate 0 (threshold documented):** Baseline ≥ 8/10 → the skill system mostly works; the reported
failure is a specific-session issue (different prompt context/model/plugin state). Investigate separately,
note the 20% miss rate is the exact reported failure class, and treat the plan as complete only if the
baseline exceeds it convincingly. Only proceed with interventions if baseline < 8/10.

---

☐ **Slice 1: Mechanism verification — Claude vs Copilot payloads (with gate)**
Type: HITL
Size: M
Blocked by: none (parallel-safe with 0)
Steps:
1. **Feasibility check first:** can Copilot's actual request payload be captured at all? Closed
   extension + no proxy → may be unbuildable. If not feasible, record that and downgrade this slice
2. Claude: capture the model-visible tools/attachments in a fresh session — confirm skills are (a) text
   blob attachment + one generic `Skill` tool, or (b) individual tools. Use the session-dir sidecars
   (`tools_*.json`/`system_prompt_*.json`) or logged request
3. Copilot: if feasible, capture its payload — confirm per-skill tool entries vs progressive blob
4. Document evidence (quotes/paths) in `working/research/skill-mechanism.md`

**Decision gate 1:** If both harnesses use the same mechanism → the Copilot-vs-Claude framing collapses;
re-scope Slices 2-5 (the fix targets something else — model, hook, plugin). If they differ → continue as
planned. This gate fires BEFORE any intervention, so a wrong mechanism theory can't drive the build.

Acceptance criteria:
- Feasibility determined first (no scheduling a slice that can't run)
- Actual payload evidence, not documentation inference

Feedback loops: manual inspection; no build yet

---

☐ **Slice 2: Intervention #1 — disable plugin skills, remeasure (LARGEST token mover)**
Type: HITL (config change, taste on ordering)
Size: S
Blocked by: Slice 0 (baseline)
Steps:
1. Disable the superpowers plugin skills for the measurement: `enabledPlugins` → off (or blocklist
   `superpowers@claude-plugins-official`) in `~/.claude/settings.json`
2. Confirm `skill_listing` shrinks (~28 plugin entries → local-only + built-ins)
3. Rerun the **same 10-session measurement** (same prompt, cwd, cap, precondition)
4. Compare invocation rates; record delta

Acceptance criteria:
- Listing token count reduced; N sessions same; only the plugin setting changed
- Rate delta attributable to the plugin disable

Feedback loops: `bash bin/measure-skill-invocation.sh` (same command as Slice 0)

**Decision gate 2:** Meaningful rate gain (≥3 points) → plugin/hook injection is a real contributor;
keep the setting, consider making it the product change. No gain → bloat-from-plugins is dead as a
theory; the visibility cost isn't in the plugin listing. Either way, proceed to Slice 3 with this
intervention kept (or reverted) explicitly.

---

☐ **Slice 3: Intervention #2 — local skill pruning, remeasure (smaller mover)**
Type: HITL (triage decisions)
Size: M
Blocked by: Slice 2 (only if plugin disable alone wasn't decisive)
Steps:
1. Reduce the local-skill listing (~54 → ~20) WITHOUT moving files:
   - Primary: **plugin/SKILL.md-based exclusion if a native mechanism surfaces in Slice 1** (e.g. a
     Claude-supported list), OR
   - Fallback: move to `skills/_local/` (gitignored — explicit sync-tracking tradeoff documented), OR
   - **Unresolved:** the symlink means a bootstrap-read manifest can't filter Claude's enumeration —
     the only clean lever is the native mechanism or a change to the deployment model (materialized
     filtered tree like `~/.copilot/skills`). Check Slice 1 evidence before choosing
2. Rerun the 10-session measurement
3. Record before/after

Acceptance criteria:
- Listing reduced; same prompt/cwd/N; only the pruning changed
- The chosen mechanism is native or the deployment-model change is explicitly accepted

Feedback loops: `bash bin/measure-skill-invocation.sh`

**Decision gate 3:** Rate moved → keep pruning. Rate still flat → bloat hypothesis is dead; stop
intervening on catalog size; go to Slice 4.

---

☐ **Slice 4: Alternate causes — hook, model, plugin listing mechanics**
Type: HITL
Size: M
Blocked by: Slice 2 or 3 (whichever gate rejects bloat)
Steps:
1. Investigate the superpowers hook (`hook_additional_context`, 3.3K chars) — it's injected
   unconditionally and tells the model to read a catalog; test disabling it for the measurement
2. Investigate model capability: same prompt on the proxy's actual model vs a stronger model — does
   invocation rate differ by model? (The failed session was `deepseek-v4-flash`; test `claude-sonnet-5`
   fallback as a control)
3. Investigate whether the generic `Skill` tool's own description/usage is the failure point (tool
   definition quality, not catalog size)
4. Any candidate shown to move the rate becomes the intervention; rerun measurement to confirm

Acceptance criteria:
- At least one alternate cause confirmed by remeasurement
- The candidate is evidenced, not inferred

Feedback loops: `bash bin/measure-skill-invocation.sh` per candidate

---

☐ **Slice 5: Command generator — fallback only, real content**
Type: AFK
Size: L
Blocked by: gates 2-4 (only if natural-language invocation can't be fixed)
Steps:
1. Write commands whose bodies contain the skill's actual working steps (inlined from reviewed
   SKILL.md), not "Load X from Y"
2. Collision map documented in `commands/README.md`, not hidden in a script
3. Wire into bootstrap; add coverage check as a guard, not a generator

Acceptance criteria:
- Every generated command carries the skill's real procedure
- No filename-only boilerplate

Feedback loops: `bash test/skills.sh`, manual review

---

☐ **Slice 6: QA — controlled before/after, not n=1**
Type: HITL
Size: S
Blocked by: slices 2-5
Steps:
1. Rerun the full 10-session measurement post-intervention (same prompt, cwd, cap, precondition)
2. Compare to baseline with the delta stated
3. Run `bash test/run-all.sh`, bootstrap dry-run
4. Report "fixed" only on a measurable positive delta

Acceptance criteria:
- Baseline vs final documented (e.g. 3/10 → 8/10)
- Regression suite green
- No single-trial claims

Feedback loops: `bash test/run-all.sh`, `bash bin/measure-skill-invocation.sh`

---

## 4. Key Insights

```
Critical Principle: Measure the failure before designing the fix.
Why it matters: v1 was unbuildable on wrong size assumptions (31K → actually 6-8K). v2 fixed structure
  but imported a wrong field interpretation (command_permissions). Both came from not measuring.
How to apply: Slice 0 gates everything; no slice builds before a number exists.
Risk if ignored: Building the wrong thing confidently, again.
```

```
Critical Principle: Test the largest contributor first.
Why it matters: The listing is 93 entries — 28 from plugins, 54 local. Pruning local first (Slice 3)
  tests a smaller half of the bloat; disabling plugins (Slice 2) moves more tokens with a settings change.
How to apply: Plugin disable is intervention #1; local pruning is #2.
Risk if ignored: Gate reads "no movement" on an underpowered test and you abandon a true cause.
```

```
Critical Principle: A symlinked skills dir can't be filtered by a manifest you control.
Why it matters: Claude enumerates through the symlink to dotfiles/skills; a bootstrap-read .visible
  file can't hide dirs from that enumeration. Native exclusions or a materialized tree are the levers.
How to apply: Prefer native mechanisms surfaced in Slice 1; if none, the deployment-model change
  (materialized filtered tree like ~/.copilot/skills) is the honest cost.
Risk if ignored: Building a manifest that silently does nothing.
```

```
Critical Principle: Validation is not discovery. command_permissions is an allowlist; .non-discoverable-skills
  is a guard that dirs stay without SKILL.md. Neither states which skills appear in the listing.
Why it matters: Reading a field name and inferring behavior sank v1 and nearly sank v2.
How to apply: Only cite a field's semantics after confirming what it controls in the code/CI.
Risk if ignored: A "verified facts" table containing unverified inferences.
```

```
Critical Principle: A measurement harness that changes the thing it measures is worthless.
Why it matters: claude -p may inject different attachments/hooks than the interactive session that
  failed. Session cost caps change nothing about turn-1 outcome but must not change attachments.
How to apply: Hard precondition — skill_listing + hook present under -p or the harness is invalid.
Risk if ignored: A baseline measuring a code path that never fails (or always fails) in reality.
```

## 5. Dependency Graph

```
Slice 0 (baseline) ──┬── gate0: stop if rate ≥ 8/10 (tolerance documented)
                     │
                     ├──▶ Slice 1 (mechanism) [parallel-safe; gate1 BEFORE interventions]
                     │
                     ├──▶ Slice 2 (plugins first, largest mover) ── gate2 ─┐
                     │                                                      ├──▶ Slice 4 (alternate causes) ← gate2/3 say flat
                     └──▶ Slice 3 (local pruning) ── gate3 ────────────────┘          │
                                                                                      ▼
                                              gates 2-4 flat → Slice 5 (fallback generator) 
                                                          │
                                                          ▼
                                          Slice 6 (QA: full remeasure + regression)
```

**Execution order:**
1. Slice 0 + Slice 1 in parallel (measure + verify mechanism, both gated)
2. Gate 0 (is there a measurable failure?) + Gate 1 (does the mechanism differ?)
3. Slice 2 (plugins — largest mover) → Gate 2
4. Slice 3 (local pruning) → Gate 3, **or** straight to Slice 4 if gate 2 was flat
5. Slice 5 only if natural-language invocation is still broken
6. Slice 6 (QA — full remeasure, never n=1)

**Critical path:** 0 → 2 → (3|4) → 6. Slices 1 and 5 are research/fallback.

## 6. QA Plan

1. **Baseline vs final**: `bin/measure-skill-invocation.sh` once (Slice 0) and once (Slice 6); success
   requires a measurable positive delta from the same harness.
2. **Attribution**: one intervention per measurement; deltas attributable.
3. **Regression**: `bash test/run-all.sh`, bootstrap dry-run; both harnesses still load from `skills/`.
4. **No n=1**: every "fixed" is backed by the 10-session measurement.

**Rollback:** Each intervention is a separate small commit (measure → intervene → remeasure), so slices
revert independently. Plugin disable is a settings toggle — instant revert.

---

## What changed from v2 (reviewer corrections → resolution)

| v2 issue | v3 resolution |
| -------- | ------------- |
| `command_permissions` = "no commands surfaced" was wrong | Corrected: field is a permission allowlist; `~/.claude/commands/` + `/audit` existed; natural-language failure is the real target |
| Intervention tested smaller half first | Reordered: plugin disable (Slice 2, largest mover, zero new code) before local pruning (Slice 3) |
| Visibility manifest may be unbuildable | `~/.claude/skills` is a symlink; manifest can't filter. Prefer native exclusion (Slice 1) or explicit deployment-model change. `.non-discoverable-skills` verified as a guard, not a filter |
| `.non-discoverable-skills` floated as native answer | Verified it's a CI guard (dirs must lack SKILL.md) — not a discovery exclusion; removed as a solution |
| No `-p` validity check | **Hard precondition**: both attachments must arrive under `-p` or the harness is invalid |
| Cost: 60-100 real audits | **Session cap**: kill after first tool call / first N tokens; outcome resolves turn 1 |
| Slice 1 had no gate | **Gate 1**: if mechanisms match, re-scope 2-5. Also feasibility-check payload capture first |
| Gate 0 = 8/10 arbitrary | Documented as a deliberate tolerance for an explicit request — the 20% miss is the reported failure class |
| n=10 binary detection limits | Documented: only large effects detectable; 5→7 must not be read as a win unless ≥3pt with the caveat stated |