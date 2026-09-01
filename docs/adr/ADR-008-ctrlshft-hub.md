# ADR-008 — Single-source-of-truth hub for the ctrl+shft agent engine

**Status:** Accepted
**Date:** 2026-08-15
**Decision implemented:** 2026-08-18 (pilot on cmd-public → PR #19)
**Author:** Aaron Davis
**Deciders:** Maintainer (sole, at this stage)

---

## Context

Sandcastle (the GitHub agent workflow engine in `ctrlshft-public/shft/engine`) is distributed to 8 consumer repos by **vendoring a full copy** of ~101 files into each repo: the engine, templates, scripts, hooks, labels, 17 workflow YAMLs, and 2 composite actions. Updates flow through `update-sandcastle.sh` (dotfiles) and a weekly `sandcastle-drift.yml` workflow per consumer that auto-opens re-vendor PRs.

This model has produced recurring structural failures:

1. **Drift by construction.** The engine physically lives inside every consumer repo, so nightly agents propose edits to vendored engine files (`cmd-public` #7/#8/#13). We responded with three layers of scope hardening (`DEFAULT_EXCLUDED_PATHS`, `disabledWorkflows`, `scope.ts` backstops) — each a band-aid over the real problem: 84 identical copies of one source tree.
2. **Weekly re-vendor churn.** Every producer change triggers up to 8 parallel update PRs, each a merge-noise and conflict surface.
3. **No runtime single source of truth.** "Which engine version am I running?" depends on each repo's last re-vendor timestamp, and the 84-file `.sandcastle-version` manifest is drift-prone itself.
4. **Formatting/whitespace entropy.** Vendored copies introduced `prettier`/CRLF failures (arndvs #51–#53) — a symptom of files being *copied* rather than *referenced*.

The engine's own code was already designed to be hub-compatible: `resolveDefaultTemplatesDir` resolves templates relative to the workflow dir (multi-hop fallback), and `resolvePrompt` checks a consumer-local `promptDir` override before falling back to templates. The runtime contract for a hub model exists; only the distribution model needs to change.

## Decision

**Adopt a public hub repo as the single source of truth for the Sandcastle engine. Consumers reference it remotely and vendor nothing.**

### The hub

- **New public repo** (`arndvs/ctrlshft-hub`) — the sole home of:
  - the engine (`engine/` — lib, workflows, schemas, `run.ts`, tests)
  - templates (`templates/` — prompts, extractions, scripts, hooks)
  - composite actions (`actions/` — a single `agent-run` action encapsulating setup + preflight + engine run + publish + summary)
  - reusable workflows (`.github/workflows/` — `workflow_call` lifecycle jobs)
  - `labels.json`, release tooling (`hub/release.sh`)
- **Public by design**: portfolio artifact for recruiters and clients (explicit user goal), and remote `uses:` references require a public (or org-internal) repo.

### The consumers

- Keep: `sandcastle.config.json`, `CONTEXT.md`, `docs/adr/`, project prompts, secrets (unchanged).
- Replace the ~101 vendored files with:
  - N thin workflow stubs (`~3 lines` each, `uses: arndvs/ctrlshft-hub/.sandcastle/actions/agent-run@main`),
  - one `.sandcastle/hub-version.json` SHA-lock (`{ ref, lastPinnedSha, reviewedAt }`).

### Pin strategy

- Default `@main` for instant propagation, with a monthly SHA-lock review.
- A consumer may pin `hub-version.json` to a specific SHA or `vX.Y.Z` tag for stability.
- The existing `sandcastle-drift.yml` becomes a **SHA-drift check** (compare `hub-version.json` to hub latest) instead of a file-diff re-vendor.

### Migration

- **Pilot on `cmd-public`** (richest workflow surface, main dogfood repo) → baseline-compare → 1–2 week observation → roll out to the remaining 7 consumers → retire consumer-side `update-sandcastle.sh`.

## Considered Alternatives

| Alternative | Why rejected |
| --- | --- |
| **Keep vendoring, harden more** | Each hardening layer was reactive (scope exclusions, disabledWorkflows, CI gates). The failure mode — 84 copies of one engine — is structural, not a policy gap. |
| **Remote composite actions + reusable workflows, no new repo** (host actions in `ctrlshft-public`) | `ctrlshft-public` is a broad tooling repo (skills, agents, instructions, dotfiles bootstrap); the engine would share a repo with unrelated surface and the portfolio story would be muddled. A dedicated hub is cleaner and more credible. |
| **Git submodule / subtree per consumer** | Submodules are a known DX burden (every consumer dev must know submodule workflow); subtrees re-introduce copy-drift. Remote `uses:` needs no local tooling. |
| **npm package for the engine** | The engine is not a library — it's a workflow runner executed in CI with repo context. An npm distribution adds versioning ceremony without removing the workflow YAML duplication (which the hub actions solve directly). |
| **Hosted proxy / SaaS** | `ADR-004-sandcastle-hosted-proxy` covers the model-proxy layer. The hub is orthogonal: it removes engine *distribution* drift, not model access. |

## Consequences

### Positive

- **Zero drift by construction.** No vendored files → nightly agents cannot propose engine edits (the `DEFAULT_EXCLUDED_PATHS` protection becomes defense-in-depth rather than the primary guard).
- **One click updates.** `@main` + SHA-drift review replaces 8 parallel re-vendor PRs with a single hub release + per-consumer review PRs.
- **Single runtime truth.** Every consumer runs the same engine version (or an explicitly-pinned one).
- **Public portfolio artifact.** Clean, documented architecture with a clear "hub + thin consumers" story.
- **Consumer repos slim dramatically.** ~101 tracked files → ~1 config + N stubs + 1 SHA-lock.

### Negative / Costs

- **Hub becomes the availability + stability axis.** A broken push to `main` affects all consumers. Mitigated by monthly SHA-lock review and optional per-consumer pinning.
- **Composite actions add indirection.** One more hop to trace (stub → action → engine). Mitigated by single `agent-run` action and clear docs.
- **Initial migration effort.** 8 consumer repos, pilot-first, with baseline comparison.
- **`ctrlshft-public/shft/engine` becomes a pointer.** The engine's home moves to the hub; ctrlshft-public must delegate (docs, CI refs) to avoid a second engine copy.

## Migration Checklist (from the architecture doc)

1. Create hub repo (public) with README + LICENSE.
2. Move engine + tests + templates + actions + labels into hub.
3. Author `actions/agent-run` composite + reusable lifecycle workflows.
4. Author `hub/release.sh` (SHA-lock bump, tagging).
5. Pilot: migrate `cmd-public` to stubs; baseline-compare all workflows.
6. Observe 1–2 weeks; verify zero drift and no engine-change proposals.
7. Roll out to launch, aligned, PUSH, mcrdse-ops, rise-awake, arndvs, llm-gateway.
8. Retire `update-sandcastle.sh` consumer-side; migrate `sandcastle-drift.yml` to SHA-drift.
9. Add hub CI running the engine test suite on every PR.

---
