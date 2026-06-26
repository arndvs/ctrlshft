# ADR-006 — Verifiable decision history & the Decision Ledger

**Status:** Proposed
**Date:** 2026-06-26
**Author:** Aaron Davis
**Deciders:** Maintainer (sole, at this stage)

---

## Context

A Yahoo job ad asking for "10+ years of Claude Code experience" prompted a wider discussion: as agents log every decision, mistake, and outcome in persistent memory, the durable hiring/value filter shifts from *years of experience* to **verifiable decision history** — "the agents that can show their work win." The sharpest formulation: the metric that matters is the **percentage of agent decisions that survive human review unchanged** (one team reported moving it from 40% to 85%), not PR count or token usage.

A deep audit (2026-06-26, five parallel exploration sub-agents) examined ctrlshft through that lens. The finding: ctrlshft is already a partial implementation of "verifiable decision history," but the pieces are siloed and the highest-value signal is discarded.

**What already exists (the seeds):**

- Four independent decision-history substrates — the chronicle/session store (interactive sessions), the bridge/Sandcastle job ledger (`~/bridge/state.db`, autonomous runs), the HUD (`events`/`violations`/`loaded_files`), and cross-session memory (`/memories/` + self-rewriting skills).
- A three-tier verification stack — preventive hooks (`hooks/secret-guard.sh`, `git-workflow-gate.sh`, `test-gate.sh`, `migration-guard.sh`), detective skills (`skills/compliance-audit/`, `skills/pr-preflight/`), and adversarial `skills/stress-test/`.
- Explicit escalation boundaries — `skills/review-pr-copilot/` confidence tiers (Auto ≥75 / Confirm 40–74 / HITL <40) and `bridge/worker.py`'s iteration cap → `agent-loop-exceeded` label + "human review required".
- The thesis is already written in: `skills/compliance-audit/SKILL.md` states "a system with documented 85% compliance and a known improvement path is more trustworthy than one that claims 100% with no verification."

**The gaps that define the work:**

1. The four substrates share no spine — four schemas, four stores, zero foreign keys. No query answers "every decision, human and autonomous, on PR #N, and whether it survived review."
2. The verification layer's best signal is discarded — `hooks/secret-guard.sh` and the other gates deny to stderr and `exit 2`; nothing persists. A *blocked mistake* is the highest-value datapoint in a decision history, and it vanishes at session end.
3. "% survives review unchanged" exists only as three disconnected fragments — the compliance rate (`working/logs/compliance-log.md`), the Copilot fix-ratio (per-PR, on GitHub), and chronicle correction-detection (in turn text) — never reconciled into one trend-able number.

---

## Decision

Treat **verifiable decision history** as a first-class architectural concern, and converge the four existing substrates toward a single **Decision Ledger** rather than adding a fifth silo.

The foundational, immediately-actionable move is to **stop discarding verification events**: the preventive hooks must emit a structured, persisted `decision.blocked` / `decision.fixed` event (redacted — never the raw command) so caught mistakes become part of the record.

On top of that, compute the one metric the trend converges on — **% of agent decisions that survive human review unchanged** — by reconciling the three existing fragments into a single queryable figure over time.

The work is sequenced A→E (full slice detail, acceptance criteria, and feedback loops live in the implementation plan `working/active/decision-ledger.md`):

| # | Slice | Type | Why |
|---|-------|------|-----|
| A | Persist verification events (`decision.blocked`) | AFK | Makes the record honest; unblocks everything. Highest leverage, lowest effort |
| B | Single survive-review metric | AFK | The number that replaces "years of experience" |
| C | Unified Decision Ledger (query surface over the four substrates) | HITL→AFK | Deepens four shallow stores behind one interface |
| D | Adaptive escalation thresholds (recommend-only) | HITL | Self-tunes autonomy from the ledger |
| E | Exportable, signed "show-your-work" credential | HITL | The portable artifact the hiring filter will demand |

This ADR records the **direction**. The specific Decision Ledger interface (event-sourced log vs. SQLite view over the existing stores vs. read-time fan-out) is deferred to an RFC produced in Slice C.

---

## Consequences

**Positive:**

- Caught mistakes (blocked/denied actions) become durable, queryable evidence — the most valuable rows in a decision history, currently thrown away.
- A single, defensible "survive-review rate" replaces three disconnected proxies — the metric that maps directly to the emerging market filter.
- ctrlshft can produce an exportable, signed record of how its agents actually decide — turning "I ran N agent-hours" into provable decision history.
- Builds on existing infrastructure (HUD transport, compliance-log, chronicle) rather than introducing a new system.

**Negative:**

- The append-only `working/logs/decisions.jsonl` is another runtime artifact that needs rotation/bounds (`rules/resource-management.md`).
- Persisting denial events carries a secrets-exposure risk if implemented naively — the secret-guard command *contains* the secret it guards. Mitigation (logging only the matched rule/pattern, plus a redaction pass) is mandatory, not optional.
- A unified ledger (Slice C) couples four previously-independent stores; the interface choice constrains future schema changes.

**Neutral:**

- The ledger observes and records; it does not change agent behaviour. Enforcement stays in hooks and rules — consistent with ADR-003's read-only HUD principle.
- Adaptive thresholds (Slice D) remain recommend-only — autonomy boundaries never move without human sign-off.

---

## Alternatives considered

**Status quo — keep the four substrates separate.** Rejected: the data exists but cannot be joined, so the one metric that matters can't be computed and caught mistakes stay invisible.

**Single rewrite into one new event store.** Replace chronicle + bridge DB + HUD with one unified store. Rejected: high-risk, discards working infrastructure; a read-time query surface over the existing stores reaches the same goal incrementally.

**External observability SaaS (Datadog/Honeycomb) for the decision stream.** Rejected for the same reason as ADR-003 — adds a cloud dependency and credential surface to a local-first, self-contained tool, and the signal (rule compliance, review-survival) is too domain-specific for generic APM.

---

## References

- Implementation plan (disposable, slice-level detail): `working/active/decision-ledger.md`
- ADR-003 (HUD observability) — the real-time event layer this builds on
- Audit evidence: `skills/compliance-audit/SKILL.md`, `bridge/worker.py`, `hooks/secret-guard.sh`, `bin/hud-daemon.js`
