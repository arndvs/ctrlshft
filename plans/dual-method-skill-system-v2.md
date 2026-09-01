# Implementation Plan v2: Skill Invocation Fix — Measurement-First

**Supersedes:** `plans/dual-method-skill-system.md` (v1, rejected)
**Status:** DRAFT — pending Slice 0 baseline
**Reviewer findings addressed:** token claim (unverified), mechanism claim (unverified), missing baseline,
Slice 3 vs 4 contradiction, boilerplate commands, `_local/` sync cost, waved-off constraint, n=1 QA.

---

## 1. Context

A Claude Code session typed "is the readme accurate to the codebase repo? codebase audit" and the
`codebase-audit` skill did not load — zero `Skill` tool calls across the whole session, despite the skill
being present in the session's `skill_listing` with a matching trigger. A prior plan (v1) proposed a
six-slice build (command generator, catalog pruning, routing table) without first measuring the failure.
Independent review found the plan's central numbers unverified (~31K-token catalog claim was actually
~6-8K, descriptions-only) and its mechanism claim unverified (Copilot "first-class tools" vs Claude
"text blob" was inferred, not observed). The review's prescription: **measure → verify → one
intervention → remeasure → only then build.** This plan follows that order. No build happens until a
baseline exists.

**Notable verified facts (Slice 0 groundwork, already measured):**

| Claim | Verdict | Evidence |
| ----- | ------- | -------- |
| ~125K chars / ~31K token skill catalog | **False** | `skill_listing` attachment = 24,679 chars ≈ 6-8K tokens, 93 entries (incl. plugin skills), name+description only |
| `/audit` existed in the failed session | **False** | `command_permissions` = `{"allowedTools": []}` — no commands were surfaced at all |
| `codebase-audit` present with trigger | True | `skill_listing` contained it verbatim |
| Superpowers hook fired | True | `hook_additional_context` (3.3K chars) injected at session start |
| Prior plan "collapsed 42→55" | **Garbled** | progressive-disclosure merged at 21 shared skills; 54 now — direction was a reduction, framing was wrong |
| `disable-model-invocation` broke VS Code | Unverified | earlier plan note; never investigated what actually broke |

## 2. Design Decisions

| Decision | Choice |
| -------- | ------ |
| Build gate | **No build until Slice 0 baseline exists and a decision gate passes** |
| Measurement | Fresh-session invocation rate: same prompt, N sessions, count `Skill` tool calls in logs |
| Token accounting | Use real session-log token counts (via `input_tokens` in llm_request), not chars/4 |
| Mechanism verification | Inspect Copilot's actual request payload (skills in tools array?) vs Claude's (text blob + generic Skill tool) — decide via evidence, not inference |
| Intervention target | Single variable at a time: first = catalog pruning, remeasure, then decide |
| Command generator | **Deferred to fallback** — only build if pruning fails to move invocation rate |
| Generated command content | Only if built: **real dispatch content** (skill's own steps inlined), never filename-only boilerplate |
| `_local/` move | Explicit sync/tracking decision required first (gitignore cost) — tracked alternative: keep in `skills/` but exclude via a visibility manifest |
| `disable-model-invocation` | **Not used in v2** until the prior VS Code breakage is investigated and understood |
| Routing table | Only if pruning proves bloat; then measured, not assumed |
| Slice structure | Vertical, each with acceptance criteria + feedback loop; decision gates between slices, not after |

## 3. Vertical Slices

---

☐ **Slice 0: Baseline measurement (BLOCKING — everything waits on this)**
Type: AFK (mechanical) with HITL interpretation
Size: S
Blocked by: none
Steps:
1. Write `bin/measure-skill-invocation.sh`: takes a prompt + session count, spawns N fresh Claude Code
   sessions (non-interactive, `-p` mode) against a fixed cwd, then greps each session log
   (`~/.claude/projects/<project>/*.jsonl`) for `Skill` tool calls and `attributionSkill` markers
2. Prompt: the exact failing prompt — "is the readme accurate to the codebase repo? codebase audit"
   (run in `agentic-nlq` cwd; fallback: any small repo)
3. Run **10 sessions**, record invocation rate (X/10)
4. Capture per-session context: `input_tokens` of the first `llm_request` (real token cost, not chars/4),
   and whether `skill_listing` + `hook_additional_context` were both present
5. Write result to `working/research/skill-invocation-baseline.md`

Acceptance criteria:
- Measured invocation rate with a real number (e.g. baseline = 3/10), not "sometimes"
- Per-session token counts recorded
- Reproducible: same prompt + cwd reruns produce same command

Feedback loops: `bash bin/measure-skill-invocation.sh`, manual log inspection

**Decision gate 0:** If baseline ≥ 8/10 → the skill system works; investigate the original session's
specific failure separately (different prompt context, model, plugin state). Stop this plan. Only proceed
if baseline < 8/10.

---

☐ **Slice 1: Mechanism verification (Claude vs Copilot payloads)**
Type: HITL (requires running both harnesses + inspecting requests)
Size: M
Blocked by: none (parallel-safe with 0)
Steps:
1. Claude: capture the actual request payload sent to the model in a fresh session — confirm whether
   skills are (a) a text blob attachment + one generic `Skill` tool, or (b) individual tools. Evidence:
   the model's tools array in the logged request, or the `tools_*.json`/`system_prompt_*.json` sidecar
   in the session dir
2. Copilot: capture its actual request payload — confirm whether each skill is a first-class tool entry
   (with per-skill description) or a progressive-loading blob. Use the Copilot debug log
   (`~/.copilot/logs/` or the IDE session log) or a proxy capture if available
3. Document the real difference (or sameness) in `working/research/skill-mechanism.md`
4. If both harnesses use the same mechanism → the "Copilot works, Claude doesn't" framing is wrong and
   the fix targets something else entirely (e.g. model, plugin, hook)

Acceptance criteria:
- Actual payloads inspected, not inferred — with quotes/paths as evidence
- The mechanism claim is confirmed or refuted with evidence

Feedback loops: manual inspection; no build yet

---

☐ **Slice 2: Single intervention — catalog visibility (prune), then remeasure**
Type: HITL (triage decisions)
Size: M
Blocked by: Slice 0 (need baseline to compare)
Steps:
1. Decide the intervention: reduce the `skill_listing` the model sees. Options (pick ONE):
   a. Move rare skills to `_local/` (existing mechanism, but note gitignore cost — see decision table)
   b. **Visibility manifest** (preferred, no move): new `skills/.visible` or frontmatter flag read by
      `bootstrap.sh` + `materialize_copilot_skills` to exclude from the Claude `skill_listing` while
      keeping the files tracked and synced
2. Implement the minimal exclusion (option b preferred — no `git mv`, no sync loss)
3. Rerun the **same 10-session measurement** from Slice 0
4. Compare invocation rates; record both in the baseline research doc

Acceptance criteria:
- Same prompt, same cwd, same N sessions; only the intervention changed
- Before/after rates recorded; deltas attributable to the intervention
- `_local/` not used unless the sync cost was explicitly accepted

Feedback loops: `bash bin/measure-skill-invocation.sh` (same command as Slice 0)

**Decision gate1:** If invocation rate moved up meaningfully (≥3 point gain) → bloat hypothesis holds;
continue to Slice 3 (routing, measured). If unchanged → bloat hypothesis is wrong; do NOT build routing
or generator; go to Slice 4 (alternate causes).

---

☐ **Slice 3: Routing table — only if pruning helped, and measured afterward**
Type: HITL
Size: S
Blocked by: Slice 2 (decision gate1 must say "continue")
Steps:
1. Add a compact "Skill Routing" table to `CLAUDE.base.md` — only the skills that were failing to
   auto-invoke, not all 54
2. Regenerate `CLAUDE.md` + `copilot-instructions.md` via bootstrap
3. Rerun the 10-session measurement a third time
4. If routing table alone suffices without pruning (test separately if useful), keep only whichever
   intervention worked; drop the other

Acceptance criteria:
- Net token delta of the routing table is small (<500 tokens)
- Third measurement shows no regression vs Slice 2 result
- Only failing skills get routing rows

Feedback loops: `bash bootstrap.sh`, `bash bin/measure-skill-invocation.sh`

---

☐ **Slice 4: Alternate causes — only if pruning failed (decision gate1 = "stop")**
Type: HITL
Size: M
Blocked by: Slice 2, only if gate1 rejects bloat
Steps:
1. Investigate the superpowers hook (`hook_additional_context`, 3.3K chars) — is it crowding the
   catalog it tells the model to read? Test disabling it for the measurement prompt
2. Investigate model: same prompt on the proxy's actual model vs a stronger model — does invocation
   rate differ by model?
3. Investigate the plugin skill listing (`dataviz`, `superpowers:*` entries — 93 total vs 54 local) —
   is plugin noise the real bloat?
4. Any cause shown to move the rate becomes the intervention; rerun measurement to confirm

Acceptance criteria:
- At least one alternate cause identified that explains the baseline failure
- Confirmed by remeasurement, not inference

Feedback loops: `bash bin/measure-skill-invocation.sh` after each candidate

---

☐ **Slice 5: Command generator — only as fallback, with real content**
Type: AFK
Size: L
Blocked by: gates 0/1 (only if natural-language invocation can't be fixed by 2/3/4)
Steps:
1. Do NOT generate boilerplate. For each skill that must be reachable: write a command whose body
   contains the skill's actual working steps (inlined from the reviewed SKILL.md), not
   "Load the <skill> skill from <path>"
2. Collision map kept in `commands/README.md` (documented), not hidden in a script
3. Wire into bootstrap; add coverage check as a guard, not a generator

Acceptance criteria:
- Every generated command carries the skill's real procedure
- No "filename-only boilerplate" commands exist

Feedback loops: `bash test/skills.sh`, manual review of generated bodies

---

☐ **Slice 6: QA — controlled before/after, not n=1**
Type: HITL
Size: S
Blocked by: slices 2-5 (whatever shipped)
Steps:
1. Rerun the **full 10-session measurement** (same prompt, same cwd) post-intervention
2. Compare to baseline from Slice 0 with the delta stated
3. Run the harness regression suite (`bash test/run-all.sh`), bootstrap dry-run
4. Only report "fixed" if the invocation-rate delta is measurable and positive

Acceptance criteria:
- Clear before/after invocation rate documented (e.g. 3/10 → 8/10)
- Regression suite green
- No "works in my one test" claims

Feedback loops: `bash test/run-all.sh`, `bash bin/measure-skill-invocation.sh`

---

## 4. Key Insights

```
Critical Principle: Measure the failure before designing the fix.
Why it matters: v1 was unbuildable because its size assumptions (31K tokens) were wrong by 4-5x
  and its mechanism claims were inferred. A 30-minute measurement (Slice 0) now gates the entire plan.
How to apply: Every slice beyond 0 is conditional on the previous measurement's result.
Risk if ignored: Building the wrong thing confidently, again.
```

```
Critical Principle: One intervention per measurement cycle.
Why it matters: The failure is probabilistic; stacking changes makes deltas uninterpretable.
How to apply: Prune → remeasure → decide. Route → remeasure → decide. Never both at once.
Risk if ignored: You ship a "fix" you can't attribute and can't reproduce.
```

```
Critical Principle: Verify the mechanism in the request payload, not in the documentation.
Why it matters: The Copilot-vs-Claude mechanism theory is the load-bearing wall of the redesign,
  and it was never observed. Docs describe intent; payloads describe behavior.
How to apply: Capture and quote actual requests from both harnesses before deciding what to change.
Risk if ignored: A redesign built on a false mechanism assumption.
```

```
Critical Principle: No token moves into permanent context without measuring its effect.
Why it matters: v1's routing table contradicted its own bloat thesis (added always-loaded rows to fix
  oversubscribed permanent context). Measured routing (Slice 3) avoids this.
How to apply: If bloat is the cause, subtract tokens; don't add them. If routing is used, it must be
  small and remeasured.
Risk if ignored: Making the diagnosed problem worse in the name of fixing it.
```

```
Critical Principle: Generated commands must carry information, or not exist.
Why it matters: 38 files of "Load X skill from Y. Execute." add listing cost and zero dispatch value.
How to apply: Inline the skill's real procedure into the command body, or don't generate.
Risk if ignored: A catalog of inert boilerplate that itself becomes bloat.
```

## 5. Dependency Graph

```
Slice 0 (baseline) ──┬── gate0: stop if rate ≥ 8/10
                     │
                     ├──▶ Slice 1 (mechanism)  [parallel-safe with 0]
                     │
                     ├──▶ Slice 2 (prune + remeasure) ── gate1 ──┬── yes → Slice 3 (routing + remeasure)
                     │                                           └── no  → Slice 4 (alternate causes)
                     │
                     └──▶ [gates 0/1 fail to fix] → Slice 5 (real-content commands, fallback only)
                                                          │
                                                          ▼
                                          Slice 6 (QA: full remeasure + regression)
```

**Execution order:**
1. Slice 0 + Slice 1 in parallel (measure + verify mechanism)
2. Decision gate 0 (is there even a measurable failure?)
3. Slice 2 (one intervention) → decision gate 1
4. Slice 3 **or** Slice 4 (whichever gate 1 selects)
5. Slice 5 only if natural-language invocation is still broken after 2-4
6. Slice 6 (QA — full remeasure, never n=1)

**Critical path is short:** 0 → 2 → (3|4) → 6. Slices 1 and 5 are research/fallback, not core.

## 6. QA Plan

1. **Baseline vs final**: run `bin/measure-skill-invocation.sh` once (Slice 0) and once more (Slice 6);
   the plan only reports success if the invocation rate moves measurably and positively.
2. **Attribution**: every slice between baseline and final changed exactly one thing; deltas are
   attributable.
3. **Regression**: `bash test/run-all.sh`, bootstrap dry-run, both harnesses still load skills from the
   single `skills/` source.
4. **No n=1**: every claim of "fixed" is backed by the 10-session measurement, not a single try.

**Rollback:** Each intervention is a separate, small commit (measure → intervene → remeasure), so any
slice can be reverted independently. No build happens unless measurement says it should.

---

## What this plan fixes vs v1 (reviewer findings → resolution)

| v1 flaw | v2 resolution |
| -------- | ------------- |
| Unverified 31K-token claim | Slice 0 measures real input_tokens; 24.7K chars ≈ 6-8K tokens already documented |
| Unverified mechanism claim | Slice 1 inspects actual payloads from both harnesses |
| No baseline; n=1 QA | Slice 0 baseline + Slice 6 full remeasure; only measurable deltas are reported |
| Slice 3-vs-4 contradiction | Routing (Slice 3) is conditional on gate1 and remeasured; never added unconditionally |
| Boilerplate commands | Slice 5 (fallback) inlines real procedure per command, or doesn't publish |
| `_local/` sync cost | Preference for a visibility manifest (option b) — no move, no gitignore loss |
| `disable-model-invocation` waved off | Not used in v2 until the prior VS Code breakage is investigated (Slice 4 candidate) |
| "Collapsed 42→55" garbled fact | Corrected in Context table: 21 at merge → 54 now; framing fixed |
| Wrong claim that `/audit` existed in-session | Documented: `command_permissions` = empty `allowedTools`; no commands were surfaced at all |