# Artifact Lifecycle

How files move through the ctrl+shft system — from raw reference material to permanent documentation or deletion.

> **Canonical source.** This document defines the lifecycle for all working artifacts, plans, research, and documentation in ctrl+shft repos. Agent instructions and skills reference this document rather than defining their own conventions.

---

## Lifecycle Flow

```
refs → research → active plan → ship
                                  ├── docs/adr/       (decisions)
                                  ├── docs/research/   (durable synthesis)
                                  ├── docs/audits/     (assessment artifacts)
                                  ├── GitHub Issues     (issue slices)
                                  └── delete            (everything else)
```

### 1. Refs

Raw external material enters `working/refs/`. Each ref must include provenance — source URL, date fetched, and why it was collected. Refs are inputs, not outputs.

```markdown
<!-- working/refs/some-api-docs.md -->
# Some API Documentation

Source: https://example.com/api/v2/docs
Fetched: 2026-06-08
Context: Evaluating auth options for issue #42

[content or summary here]
```

### 2. Research

The research skill synthesizes refs into `working/research/<topic>.md`. Research documents contain analysis, conclusions, trade-offs, and option comparisons. They live until the feature ships.

Research is a working document — delete it when the work that created it is complete. If the synthesis has lasting value beyond the immediate task, promote it to `docs/research/`.

### 3. Active Plan

Research informs execution plans in `working/active/<topic>.md`. These are created by the handoff protocol when a task spans multiple conversations. Each plan includes:

- Current slice details and acceptance criteria
- What's done vs. what remains
- Pickup command for the next conversation

Active plans are disposable — delete them when the work ships.

### 4. Ship

When work completes, artifacts graduate or die:

| Artifact | Destination | When |
|----------|-------------|------|
| Architecture decisions | `docs/adr/ADR-NNN-<topic>.md` | Decision has long-term implications |
| Durable synthesis | `docs/research/<topic>.md` | Analysis outlives the task that created it |
| Assessment findings | `docs/audits/<topic>.md` | Audit results worth preserving |
| Task slices | GitHub Issues | Planned work not yet started |
| Everything else | Delete | Plans, refs, research consumed by the task |

---

## Directory Map

### `working/` — Scratch and Execution

The workspace for in-progress tasks. Contains both tracked markdown that agents need and ignored runtime noise.

#### Tracked lanes (committed to git)

| Directory | Purpose | Lifecycle |
|-----------|---------|-----------|
| `working/active/` | Execution plans for in-progress work | Delete when work ships |
| `working/refs/` | Reference pointers and third-party material | Delete when consumed by research or plan |
| `working/research/` | Synthesized exploration artifacts | Delete when work ships; promote to `docs/research/` if durable |

#### Ignored lanes (gitignored)

| Directory | Purpose | Examples |
|-----------|---------|----------|
| `working/runtime/` | Auto-generated state files | `active-client.md`, `shft-state.json` |
| `working/tmp/` | Temporary task artifacts | PR review JSON, scratch computations |
| `working/logs/` | Execution and event logs | `afk-iter-*-stderr.log`, `events.jsonl`, `compliance-log.md` |

#### Root-level files

`working/` root should not contain loose files. Active plans belong in `working/active/`, research in `working/research/`, refs in `working/refs/`. Runtime-generated files belong in `working/runtime/` or `working/logs/`.

### `plans/` — Formal PRDs and Issue Breakdowns

Created by `/write-a-prd` and `/prd-to-issues`. These are formal product requirements documents and their issue decompositions.

| Directory | Purpose | Lifecycle |
|-----------|---------|-----------|
| `plans/` | PRD documents | Archive or delete after work completes |
| `plans/issues/` | Issue slice breakdowns from PRDs | Delete after issues are created in GitHub |

Plans are distinct from active execution files in `working/active/`. A PRD defines *what* to build; an active plan tracks *where you are* in building it.

### `docs/` — Permanent Documentation

Durable artifacts that outlive the task that created them. Nothing in `docs/` is disposable.

| Directory | Purpose | Examples |
|-----------|---------|----------|
| `docs/adr/` | Architecture Decision Records | `ADR-001-vendor-boundary.md` |
| `docs/reference/` | Durable reference material | Design systems, course materials, API guides |
| `docs/research/` | Promoted research with lasting value | Synthesis docs that outlive their originating task |
| `docs/audits/` | Dated assessment artifacts | Codebase audits, parity checks, compliance reports |
| `docs/docs/` | Public documentation site source | Next.js app for ctrl+shft docs |
| `docs/mechanisms/` | External submodules | `claude-mechanisms/`, `claude-mechanisms-tools/` |

### `~/.claude/plans/` — Plan-Mode Output (separate system)

Plan-mode files managed by the `/plan-archive` skill live in `~/.claude/plans/`. This is a separate system from `working/active/` and `plans/`. The `/plan-archive` skill archives these to `~/.claude/plans/archive/by-pr/` after PRs merge.

---

## Discoverability Rule

**Agent-useful markdown must be tracked in git or summarized in a tracked file.**

Agents rely on git-tracked files for context. If a file is gitignored, agents can't find it in future sessions. This creates a hard boundary:

- **Tracked:** `working/active/*.md`, `working/refs/**/*.md`, `working/research/*.md` — agents read these for context
- **Ignored:** `working/runtime/`, `working/tmp/`, `working/logs/` — noise that agents don't need across sessions

Never blanket-ignore `working/`. Ignore specific subdirectories that contain runtime noise, not the entire tree.

If a runtime process generates information that agents need in future sessions, that information must be summarized in a tracked file. For example, `compliance-log.md` (a cross-session persistent log) belongs in `working/logs/` (ignored) but its actionable findings should be captured in tracked issues or docs.

---

## Provenance Requirements

Third-party refs in `working/refs/` must include:

| Field | Required | Purpose |
|-------|----------|---------|
| **Source** | Yes | URL or file path where the material originated |
| **Fetched** | Yes | Date the material was captured |
| **Context** | Yes | Why this ref was collected (task, issue number, question) |
| **License** | If applicable | License terms for redistributable content |
| **Expiry** | If applicable | When the ref may become stale (API version EOL, etc.) |

Refs without provenance are unverifiable — if you can't trace where it came from, don't commit it.

Content in `docs/reference/` has weaker provenance requirements since it represents curated, long-lived material. But source attribution is still expected where the material originated externally.

---

## Migration Path

For repos adopting this lifecycle, the migration sequence is:

1. Create tracked directories with README placeholders (`working/active/`, `working/refs/`, `working/research/`, `docs/reference/`, `docs/research/`, `docs/audits/`)
2. Add gitignore rules for `working/runtime/`, `working/tmp/`, `working/logs/`
3. Classify existing loose files in `working/` into the appropriate lane
4. Move active plans to `working/active/`
5. Move promoted research/synthesis to `docs/research/`
6. Move audit artifacts to `docs/audits/`
7. Update agent instructions and skills to reference lifecycle paths
8. Run the lifecycle audit command to verify placement

---

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| Loose files in `working/` root | Ambiguous lifecycle — plan? research? runtime? | Move to the appropriate subdirectory |
| `docs/` as a plan bucket | Plans are disposable; docs are permanent | Plans go in `working/active/` or `plans/` |
| Blanket-ignoring `working/` | Hides agent-useful markdown | Ignore specific subdirectories, not the tree |
| Promoted plan still in `working/` | Creates two copies, drift risk | Delete the working copy after promotion |
| Refs without provenance | Can't verify source, can't assess staleness | Always include source, date, context |
| `research.md` at project root | No lifecycle path, easy to forget | Use `working/research/<topic>.md` |
