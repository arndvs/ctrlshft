# Implementation Plan v4: Skill Invocation Fix — Model-First, Measurement-Driven

**Supersedes:** `plans/dual-method-skill-system.md` (v1), `-v2.md`, `-v3.md`
**Status:** DRAFT — pending Slice 0 baseline
**Reviewer v3 corrections:** model hypothesis promoted to front, variable-splitting (hook vs plugin),
per-source char counts, session-cap false-negative fix, Slice 3 dependency fix, gate-0 wording.

---

## 1. Context

A Claude Code session typed "is the readme accurate to the codebase repo? codebase audit" and the
`codebase-audit` skill did not load — zero `Skill` tool calls across 174 messages, despite the skill
being present in the session `skill_listing` (93 entries) with a matching trigger, and the superpowers
`hook_additional_context` (3.3K chars) telling the model to read it.

**The single most important verified fact: the failed session ran `deepseek/deepseek-v4-flash-0731`
through the LiteLLM proxy.** Claude Code routes every `claude-*` model name to DeepSeek by default
(primary) with `github_copilot/claude-sonnet-5` as fallback. The Copilot extension does **not** route
through this proxy at all — it uses Copilot's own model endpoints directly (Sonnet/Opus).

So the observable "Copilot follows skills, Claude CLI doesn't" is most plausibly explained by
**deepseek-vs-Sonnet**, not by a harness-architecture difference. That hypothesis was abandoned in
conversation when the user asserted "same model" — but the assertion was about the proxy's label
(which routes to DeepSeek), not about what Copilot actually serves. The cheapest possible intervention —
point the proxy at the already-configured `github_copilot/claude-sonnet-5` fallback — tests the
highest-prior hypothesis with a one-line config change. It runs as **Slice 2**, ahead of all catalog work.

**Verified facts (plan inputs):**

| Fact | Status | Evidence |
| ---- | ------ | -------- |
| Failed session model = `deepseek-v4-flash-0731` | ✅ | 174 messages logged |
| Claude CLI routes all `claude-*` → DeepSeek (primary), Sonnet fallback | ✅ | `litellm_config.yaml` model_list |
| Copilot extension does NOT use the proxy | ✅ | separate Copilot endpoints; proxy serves Claude Code |
| Superpowers `hook_additional_context` ships with the plugin | ✅ | `hooks/session-start` reads `skills/using-superpowers/SKILL.md` |
| `skill_listing` = 24,679 chars ≈ 6-8K tokens, 93 entries | ✅ | session log attachment |
| …~54 local, ~28 plugin, ~11 built-in (char counts per source pending Slice 0) | ⏳ | entry counts measured; char split = Slice 0 output |
| `disable-model-invocation` is CI-deprecated | ✅ | README Integrity checks |
| `.non-discoverable-skills` is a guard (dirs must lack SKILL.md), not a filter | ✅ | `config-consistency.sh` Invariant 5 |
| `command_permissions` is a permission allowlist, not command discovery | ✅ | field semantics; `/audit` existed on disk |

---

## 2. Design Decisions

| Decision | Choice |
| -------- | ------ |
| Highest-priority hypothesis | **Model capability** (deepseek vs sonnet) — tested first, cheapest, one-line config |
| Build gate | No build until Slice 0 baseline exists |
| Measurement | Fresh-session invocation rate; same prompt, N sessions, count `Skill` calls |
| Session harness | `claude -p` with hard validity precondition (attachments must arrive under `-p`) |
| Session cost cap | **Cap on token budget or 3-4 tool calls — NOT first-tool-call** (a model that reads README then loads skill shouldn't be a false negative) |
| Listing accounting | Slice 0 emits **char counts per source** (local / plugin / built-in) so ordering rests on measurement |
| Intervention order | Model swap (2) → hook disable (3) → plugin skills disable (4) → local pruning (5, only if 2-4 flat) |
| Variable splitting | Hook and plugin skills tested **separately** (disable hook alone first; then plugin skills alone) — never together |
| Plugin disable scope | Disable `enabledPlugins: superpowers` only after the hook is tested in isolation |
| Model swap | Point `claude-opus-5` at `github_copilot/claude-sonnet-5` fallback (already configured) — one-line config |
| Visibility lever | Only if 2-4 flat: check for a **native skill-exclusion in `~/.claude/settings.json` schema** first; else materialized filtered tree (deployment-model change, priced before scheduling) |
| `disable-model-invocation` | **Not used** — CI fails on it |
| Command generator | **Fallback only** — if natural-language invocation can't be fixed by 2-5 |

## 3. Vertical Slices

---

☐ **Slice 0: Baseline measurement (BLOCKING)**
Type: AFK + HITL interpretation
Size: S
Blocked by: none
Steps:
1. Write `bin/measure-skill-invocation.sh`:
   - Spawn N fresh Claude Code sessions (fixed prompt + cwd)
   - **Validity precondition (hard stop):** each session must contain BOTH `skill_listing` and
     `hook_additional_context`; if `-p` omits either, harness is invalid → switch capture method
   - **Cost cap:** terminate at a **token budget or after 3-4 tool calls** (NOT the first) — the
     outcome is "did `Skill` get called across a few turns", not "was it called first"
   - Parse `skill_listing` → emit **char counts per source**: local / plugin / built-in
   - Grep logs for `Skill` calls + `attributionSkill`; record first-`llm_request` `input_tokens`
2. Prompt: "is the readme accurate to the codebase repo? codebase audit" (in `agentic-nlq` cwd)
3. Run 10 sessions; record invocation rate + per-source char counts
4. Write to `working/research/skill-invocation-baseline.md`

Acceptance criteria:
- Invocation rate (X/10), per-source char counts, per-session tokens all recorded
- Precondition documented; sessions capped on tokens (not first call)

Feedback loops: `bash bin/measure-skill-invocation.sh`, manual log inspection

**Decision gate 0:** Baseline ≥ 8/10 → the system mostly works for this prompt; investigate the specific
failed session separately (different context/model/plugin state). Proceed with interventions only if
baseline < 8/10. **Wording fixed:** 8/10 is the stop threshold, period — no "complete only if it
exceeds convincingly" ambiguity.

---

☐ **Slice 1: Verify Copilot's actual model (cross-harness framing survival check)**
Type: AFK (lookup) — quick
Size: S
Blocked by: none (parallel-safe with 0)
Steps:
1. Determine what model the Copilot extension is actually serving (Copilot settings/account UI, or
   capture from a Copilot request / its model selector)
2. Compare: is Copilot on Sonnet/Opus while Claude CLI is on DeepSeek?
3. Record in `working/research/skill-mechanism.md`

**Decision gate 1:** If Copilot = Sonnet/Opus and Claude CLI = DeepSeek → **the model hypothesis
survives**; Slice 2 is the primary intervention and the harness-architecture theory is deprioritized.
If Copilot is ALSO DeepSeek → the cross-harness framing collapses; skip to Slice 4-style hook/plugin
testing without the model swap being primary.

Acceptance criteria:
- Copilot's actual model identified with evidence (not assumed)
- Gate result recorded

Feedback loops: manual lookup

---

☐ **Slice 2: Intervention #1 — model swap (highest-priority hypothesis)**
Type: AFK (config change) + measurement
Size: S
Blocked by: Slice 0 (baseline), Slice 1 (gate result)
Steps:
1. Change `litellm_config.yaml`: `claude-opus-5` (or the model used) primary →
   `github_copilot/claude-sonnet-5` (fallback already configured; just promote it)
2. Confirm the session now logs `claude-sonnet-5` (not deepseek)
3. Rerun the **same 10-session measurement** (same prompt, cwd, cap — token/3-4 calls)
4. Compare rates; record delta in the baseline doc

Acceptance criteria:
- Model change confirmed in logs (one variable: model only)
- Rate delta attributable to model swap

Feedback loops: `bash bin/measure-skill-invocation.sh`

**Decision gate 2:** Rate moved meaningfully → model capability is the cause. Keep the swap; consider
making it the product default. Rate flat → model not the cause; revert the swap, proceed to Slice 3.

---

☐ **Slice 3: Intervention #2 — hook disable alone (confound-split)**
Type: HITL
Size: S
Blocked by: Slice 2 (flat result) — or run if model swap helped but the hook still deserves isolation
Steps:
1. **Disable ONLY the superpowers SessionStart hook** (keep the plugin's skills listed):
   edit `hooks.json` / settings to skip `session-start` (or matcher-scope it off) — do NOT disable
   the whole plugin
2. Confirm `hook_additional_context` is now absent from the session
3. Rerun the same 10-session measurement
4. Compare: with all 28 plugin skills still listed but NO hook injection

Acceptance criteria:
- Hook absent, skills still present (one variable: the injection)
- Rate delta attributable to the hook alone

Feedback loops: `bash bin/measure-skill-invocation.sh`

**Decision gate 3:** Hook removal moved the rate → the injection itself (not the catalog) is the
confound; the superpowers meta-instruction crowds the catalog it tells the model to read. Flat → hook
isn't the cause; proceed to Slice 4.

---

☐ **Slice 4: Intervention #3 — plugin skills disable (after hook isolated)**
Type: AFK (config toggle) + measurement
Size: S
Blocked by: Slice 3 (flat result), or if hook helped but catalog still needs testing
Steps:
1. Now disable the superpowers **plugin** (skills only; hook already gone or not-the-cause)
2. Confirm `skill_listing` drops ~28 plugin entries
3. Rerun the same 10-session measurement
4. Compare: fewer catalog entries, no plugin injection

Acceptance criteria:
- Listing shrunk by ~28 entries; only plugin membership changed
- Rate delta attributable to catalog size alone

Feedback loops: `bash bin/measure-skill-invocation.sh`

**Decision gate 4:** Rate moved → catalog size matters. Rate flat → bloat-from-count is dead;
go to Slice 5 only if a native lever exists, else stop catalog work.

---

☐ **Slice 5: Intervention #4 — local pruning (only if 2-4 all flat + a lever exists)**
Type: HITL
Size: M/L
Blocked by: Slice 4 (flat), and a **feasibility check first**
Steps:
1. **Feasibility**: does `~/.claude/settings.json` schema support excluding skills from the listing
   natively? (Check docs + schema — do NOT rely on Slice 1, which compares Claude/Copilot payloads
   and won't answer this.) Verify against `~/.claude/skills` being a symlink — a manifest read by
   bootstrap can't filter Claude's enumeration
2. If native lever: implement minimal exclusion, rerun measurement
3. If no native lever: price the deployment-model change (`~/.claude/skills` → materialized filtered
   tree like `~/.copilot/skills`) BEFORE scheduling; only proceed if the cost is accepted
4. Rerun the same 10-session measurement

Acceptance criteria:
- Native mechanism confirmed or the deployment change is explicitly priced/accepted
- Listing reduced; same prompt/cwd/N; only pruning changed

Feedback loops: `bash bin/measure-skill-invocation.sh`

---

☐ **Slice 6: Command generator — fallback only, real content**
Type: AFK
Size: L
Blocked by: gates 2-5 (only if natural-language invocation can't be fixed)
Steps:
1. Commands carry the skill's actual working steps (inlined from reviewed SKILL.md), not boilerplate
2. Collision map documented in `commands/README.md`
3. Wire into bootstrap; coverage guard, not generator

Acceptance criteria:
- Every command carries real procedure; no filename-only boilerplate

Feedback loops: `bash test/skills.sh`, manual review

---

☐ **Slice 7: QA — controlled before/after, not n=1**
Type: HITL
Size: S
Blocked by: slices 2-6
Steps:
1. Rerun the full 10-session measurement (same prompt, cwd, cap — token/3-4 calls)
2. Compare to baseline; state the delta
3. Run `bash test/run-all.sh`, bootstrap dry-run
4. Report "fixed" only on a measurable positive delta

Acceptance criteria:
- Baseline vs final documented (e.g. 1/10 → 8/10)
- Regression suite green; no single-trial claims

Feedback loops: `bash test/run-all.sh`, `bash bin/measure-skill-invocation.sh`

---

## 4. Key Insights

```
Critical Principle: The cheapest testable hypothesis runs first.
Why it matters: The model hypothesis is verified (deepseek), is a one-line config change, and matches
  the observable (Copilot=Sonnet follows skills; Claude CLI=DeepSeek ignores). Catalog work, in contrast,
  has no working implementation yet.
How to apply: Slice 2 (model swap) precedes all catalog slices.
Risk if ignored: Building catalog machinery to fix a model problem, or abandoning the true cause early.
```

```
Critical Principle: Never change two variables in one measurement.
Why it matters: Disabling the superpowers plugin removes both ~28 skills AND the 3.3K-char hook
  injection. A rate change then can't be attributed.
How to apply: Hook alone (Slice 3) before plugin skills (Slice 4). Verify each independently.
Risk if ignored: Confounded gates that prove nothing.
```

```
Critical Principle: Ordering rests on measurement, not guesswork.
Why it matters: v3's "largest mover = plugins" was challenged — by entry count, local pruning (54→20
  = 34) actually cuts more than plugin disable (~28). The honest difference is plugins are reversible
  and code-free, not larger.
How to apply: Slice 0 emits char counts per source (local/plugin/built-in) so the ordering is measured.
Risk if ignored: Priorities set by intuition flip when real numbers arrive.
```

```
Critical Principle: A cap that creates false negatives invalidates the measurement.
Why it matters: "Kill after first tool call" misses models that read a README first, then load the skill
  — the exact pattern in the failed session (Bash/Read/Glob before considering skills).
How to apply: Cap on token budget or 3-4 tool calls, not the first.
Risk if ignored: The baseline undercounts and the plan "fixes" a target it never measured.
```

```
Critical Principle: Feasibility outranks scheduling.
Why it matters: Slice 3's lever ("check Slice 1 evidence") was wrong — Slice 1 compares Claude/Copilot
  payloads and won't reveal a native exclusion setting. The real question is the settings schema + the
  symlink deployment model.
How to apply: Separate feasibility (native exclusion exist?) from mechanism (payload shape). Price the
  deployment-model change before scheduling.
Risk if ignored: Scheduling a slice that can't be implemented.
```

## 5. Dependency Graph

```
Slice 0 (baseline + per-source chars) ──┬── gate0: stop if ≥ 8/10
                                        │
                                        ├──▶ Slice 1 (verify Copilot model) ── gate1 (framing survives?)
                                        │
                                        └──▶ Slice 2 (model swap + remeasure) ── gate2 ─┐
                                                                                         │
                                        Slice 3 (hook disable alone) ◀── gate2 flat ─────┘
                                                    │
                                                    └──▶ gate3 ──▶ Slice 4 (plugin skills disable) ◀── gate2 helped
                                                                        │
                                                                        └──▶ gate4 ──▶ Slice 5 (local prune, priced)
                                                                                              │
                                        gates 2-5 flat → Slice 6 (fallback generator) ────────┘
                                                    │
                                                    ▼
                                          Slice 7 (QA: full remeasure + regression)
```

**Execution order:**
1. Slice 0 + Slice 1 in parallel (baseline + verify Copilot model)
2. Gate 0 (measurable failure?) + Gate 1 (framing survives?)
3. Slice 2 (model swap — highest-priority hypothesis) → Gate 2
4. Slice 3 (hook alone) → Gate 3, or Slice 4 (plugin skills) depending on gates
5. Slice 5 (local prune) only if 2-4 flat AND a native lever exists (priced)
6. Slice 6 (fallback) only if natural-language invocation still broken
7. Slice 7 (QA — full remeasure)

**Critical path:** 0 → 2 → (3|4) → 7. Slices 2-4 are each a config change + a rerun — if any moves the
rate, Slices 5 and 6 never get built.

## 6. QA Plan

1. **Baseline vs final**: `bin/measure-skill-invocation.sh` at Slice 0 and Slice 7; success requires a
   measurable positive delta from the same harness (same prompt, cwd, token-cap).
2. **Attribution**: one variable per slice; gates read single-variable deltas only.
3. **Regression**: `bash test/run-all.sh`, bootstrap dry-run; both harnesses still load from `skills/`.
4. **No n=1**: every "fixed" is backed by the N-session measurement; the cap avoids first-call false
   negatives so the number is honest.

**Rollback:** Each intervention is a separate small commit (measure → intervene → remeasure). The model
swap is a one-line `litellm_config.yaml` revert. Plugin/hook toggles are settings reverts.

---

## What changed from v3 (reviewer corrections → resolution)

| v3 issue | v4 resolution |
| -------- | ------------- |
| Model hypothesis buried at Slice 4 step 2 | Promoted to **Slice 2**, first intervention, one-line config change (promote existing sonnet fallback) |
| Slice 2 changed two variables (plugin skills + hook) | Split: **hook alone (Slice 3)** before **plugin skills (Slice 4)** — verified hook ships with plugin, so the split is mandatory |
| "Largest mover = plugins" didn't follow from own numbers | By entry count, local pruning cuts more (34 vs 28). Plugins go first for reversibility/code-free, and **Slice 0 emits char counts per source** so ordering is measured |
| Session cap = false negatives | Cap on **token budget or 3-4 tool calls**, not first call — matches the failed session's Bash/Read/Glob-then-consider pattern |
| Slice 3 blocked on wrong thing | Feasibility split: native skill-exclusion in settings schema, **not** Slice 1 payloads; price the materialized-tree deployment change before scheduling |
| Gate 0 wording muddled | Fixed: 8/10 is the stop threshold, period |
| Copilot model never verified | **Slice 1** verifies Copilot's actual model before any intervention; if it's also DeepSeek the framing collapses |