# ADR-007 — Executable documentation policy

**Status:** Accepted
**Date:** 2026-08-16
**Author:** Aaron Davis
**Deciders:** Maintainer (sole, at this stage)

---

## Context

Ctrl+shft holds a large body of documentation — ADRs, runbooks, knowledge bases, instructions — and enforces some of it with scripts, but most conventions live only as prose. The saas-starter audit (2026-08-16) surfaced a mature pattern: an **executable knowledge policy** in which `knowledge-policy.config.ts` declares document classes with frontmatter validators, link checks, and text rules that run in CI. Its operating thesis, stated in the starter's docs:

> "A convention is a lint rule. A fact or invariant about code is a test. Repository documents are for knowledge code cannot express."

Ctrl+shft already follows this philosophy in scattered places:

- `docs/adr/` — dated, immutable decision records with a README contract
- `docs/ARTIFACT-LIFECYCLE.md` — a lifecycle spec enforced by `bin/update-artifacts.sh`
- `docs/qa/` and `docs/audits/` — outcome artifacts with naming contracts
- `global.instructions.md` / `CLAUDE.base.md` — source-of-truth language enforced by CI (`integrity.yml` greps for the literal phrase)
- `skills/` — `validate-skills.sh` enforces frontmatter; this exact pattern.
- CI regression-guard contracts — `require-regression-guard.yml` machine-enforces a PR-body convention

But each enforcement is ad hoc. A structured policy engine would make them **declarative, uniform, and composable** — at the cost of one more concept to learn, and with the risk of over-engineering for a repo whose doc classes are few.

## Decision

**Adopt the executable-document-policy doctrine, but as a lightweight declarative contract — not a full engine.**

Ctrl+shft will NOT port the saas-starter's TypeScript `knowledge-policy` engine (its matchers/validators/evaluator are tuned for a fork-proliferation problem ctrl+shft doesn't have). Instead:

1. **Canonicalize the doctrine in this ADR** — the five rules from the saas-starter's `docs/AGENTS.md` become the repo's documented standard for what belongs in each doc class.
2. **Keep enforcement declarative and local** — each enforced doc class stays as it is today (CI grep, `validate-*` script, or workflow), because each is already a policy in its own right.
3. **Where a convention becomes multi-repo, lift it into a workflow template** (the regression-guard contract is the model) rather than into an engine — templates propagate via `init-sandcastle`/`update-sandcastle` and scale with the repo network.
4. **Adopt the policy's one missing piece**: the requirement that **every enforced convention earns a CI check** — if a convention is only prose, it is not a convention; it is a suggestion.

## Options considered

**A. Port the saas-starter's TypeScript knowledge-policy engine** — full `PathMatcher` combinators, `MetadataValidator` helpers, `evaluateKnowledgePolicy()`.
- Pros: complete, battle-tested, catches frontmatter drift uniformly.
- Cons: 30+ KB of engine code for ~5 doc classes; requires TypeScript + a run step in CI for every consumer; feels like a platform when the repo is a library of workflows. Rejected as over-engineering for this stage.

**B. Keep enforcement local + document the doctrine (adopted)** — each enforced class stays in its existing script/workflow; the ADR records the shared rule "conventions are enforced or they are aspirations."
- Pros: zero new dependency, immediately actionable, matches the repo's "small bash tools" ethos.
- Cons: enforcement exists in ~4 scattered places; a future convention might be added as prose without a check.

**C. Adopt a mid-weight "policy file" per repo** (`.ctrlshft/policy` — a list of convention → check commands) that `ctrl check` runs.
- Pros: 12-line jQuery approach, declarative registry of enforcement.
- Cons: new format to learn, would need a schema + validation, and duplicating existing CI wiring.

**Adopted: B** — with the explicit roadmap that when a third doc class should be enforced, the maintainer either (a) adds a check to `bin/validate-*.sh` (for repo-local class) or (b) adds a workflow template (for multi-repo class), never a doc convention without a check.

## Consequences

- New document classes must either ship with a validating check (repo-local script) or be rejected from `docs/`.
- The ADR itself is a doc — it proves the point: this record is the rationale that `bin/` scripts and workflows cannot express machine-checkably aside.
- A future maintainer wanting a policy engine has this ADR as the "rejected alternative" so they don't re-litigate.
- Consumer repos that adopt ctrl+shft get the *patterns* (regression-guard check, skills-lock validator, ledger gate) as templates — the doctrine travels via workflow templates, not a dependency.

## Related

- ADR-006 (Verifiable decision history) — doc policy is the mechanical spine for "show your work"; ADR-006 is the ledger.
- `docs/ARTIFACT-LIFECYCLE.md` — the artifact classes this ADR says must be enforced.
- Skills-provenance lockfile (`skills/skills-lock.json` + validators) — a concrete instance of "convention is enforced, not aspirational."