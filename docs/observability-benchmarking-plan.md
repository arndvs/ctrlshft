# ctrl+shft Observability & Benchmarking Plan

Generated: 2026-04-20  
Source: `working/planning/observability-benchmarking-plan.md` (working draft)

## Current status

Observability is **partially shipped** — compliance monitoring is live, telemetry/benchmarking is still planned.

### Shipped (Slices 6–7)

- ✅ Model variant agents (`researcher-opus`, `researcher-haiku`, `code-reviewer-opus`)
- ✅ `bin/write-hud-state.sh` — event emitter (pipe → HTTP → JSONL fallback)
- ✅ `bin/hud-daemon.js` — zero-dependency Node.js HUD server
- ✅ `bin/start-hud.sh` — daemon lifecycle manager (start/stop/status/restart/foreground)
- ✅ `hud/index.html` — real-time compliance UI (dark theme, WebSocket + adaptive polling fallback, project tabs, file inventory sidebar)
- ✅ `skills/compliance-audit/SKILL.md` — auto-invoked rule compliance check
- ✅ `skills/stress-test/SKILL.md` — adversarial rule boundary validation

### Still planned

- ⏳ Telemetry wrapper (JSONL events per shft run, token/model metadata)
- ⏳ Cost calculator (model/run/day costs from telemetry)
- ⏳ CI telemetry reports (daily markdown + badge)
- ⏳ OTEL schema discovery
- ⏳ Accuracy tracking framework
- ⏳ Final QA plan

## Why this matters

ctrl+shft currently lacks hard telemetry for:

- token usage
- cost by model/run
- accuracy/hallucination trend signals
- stakeholder-facing HUD views

This plan defines the vertical slices required to close that gap.

## Vertical slices (authoritative summary)

### AFK slices

1. **shft Telemetry Wrapper** (M)
   - emit JSONL events per run
   - preserve raw `stream-json` output
   - extract token/model metadata from run output
2. **Cost Calculator** (S)
   - compute model/run/day costs from telemetry
   - output markdown and JSON reports
3. **Model Variant Agents** (S) — **Done**
4. **CI Telemetry Reports** (M)
   - daily generated reports
   - optional README badge + alerting threshold issues

### HITL slices

1. **Enable OTEL + schema discovery** (S)
2. **Accuracy tracking framework** (M)
3. **Telemetry HUD** (L) — compliance portion shipped; telemetry views still planned
4. **Final QA plan** (M)

## Dependency order

- Start now (parallel-safe): OTEL discovery, telemetry wrapper hardening, model variant validation
- After wrapper: cost calculator + accuracy framework
- After cost + accuracy: CI reporting + HUD
- Last: integrated QA + stakeholder demo flow

## Recommended next move

- Execute the first implementation slice: **shft Telemetry Wrapper**
- Keep this file as the tracked reference from README
- Continue using `working/planning/observability-benchmarking-plan.md` as the editable working draft if needed

## Notes

- Runtime model injection is still not available for subagents; benchmark via variant agent files.
- Hallucination scoring needs human-in-the-loop input plus proxy signals.
- Prefer adding telemetry views into the existing HUD (`hud/index.html`) rather than introducing a second app.
