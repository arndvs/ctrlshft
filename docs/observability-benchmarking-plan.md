# ctrl+shft Observability & Benchmarking Plan

Generated: 2026-04-20  
Source: `working/planning/observability-benchmarking-plan.md` (working draft)

## Current status

Observability is still **planned/in progress**, with one dependency already landed:

- ✅ Model variant agents (`researcher-opus`, `researcher-haiku`, `code-reviewer-opus`) are present.
- ⏳ Telemetry wrapper, cost reports, accuracy scoring, CI reports, and dashboard are not yet implemented end-to-end.

## Why this matters

ctrl+shft currently lacks hard telemetry for:

- token usage
- cost by model/run
- accuracy/hallucination trend signals
- stakeholder-facing dashboard views

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
3. **Telemetry dashboard** (L)
4. **Final QA plan** (M)

## Dependency order

- Start now (parallel-safe): OTEL discovery, telemetry wrapper hardening, model variant validation
- After wrapper: cost calculator + accuracy framework
- After cost + accuracy: CI reporting + dashboard
- Last: integrated QA + stakeholder demo flow

## Recommended next move

- Execute the first implementation slice: **shft Telemetry Wrapper**
- Keep this file as the tracked reference from README
- Continue using `working/planning/observability-benchmarking-plan.md` as the editable working draft if needed

## Notes

- Runtime model injection is still not available for subagents; benchmark via variant agent files.
- Hallucination scoring needs human-in-the-loop input plus proxy signals.
- Prefer adding telemetry into existing `docs/` app surface rather than introducing a second dashboard app.