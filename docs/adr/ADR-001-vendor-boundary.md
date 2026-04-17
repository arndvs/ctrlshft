# ADR-001 — `_vendor` boundary and skill scope policy

**Status:** Accepted  
**Date:** 2026-04-17  
**Author:** Aaron Davis  
**Deciders:** Maintainer (sole, at this stage)

---

## Context

ctrl+shft started as a personal dotfiles system and is being opened to the broader developer community. During a forensic audit in April 2026, a `skills/_vendor/` directory was created to house six third-party skills installed from external agent frameworks (Vercel Labs, Sanity IO):

- `content-modeling-best-practices`
- `find-skills`
- `prisma-expert`
- `programmatic-seo`
- `seo-aeo-best-practices`
- `vercel-react-best-practices`

These skills were vendored to fix a real problem (bootstrap had no awareness of `~/.copilot/skills` or `~/.agents/skills`), but they represent personal stack choices, not universal workflow methods.

The audit also revealed that `bootstrap.sh` was silently copying these skills into every consumer directory (`~/.claude/skills`, `~/.copilot/skills`, `~/.agents/skills`) as part of the default install. A developer using Rails and Postgres would receive Prisma and Vercel skills with no opt-out.

This creates a structural tension: the repo promises to be "agnostic but opinionated about workflow," but shipping stack-specific third-party skills breaks that contract.

---

## Decision

**Path A is adopted: `_vendor/` is removed from the default payload entirely.**

The `skills/_vendor/` directory will be deleted from the tracked repository. It will not be replaced with an opt-in installer at this time.

The six affected skills become the user's responsibility to install via the external framework that originally managed them (`~/.agents/skills` via the agent skill marketplace), or to place manually into `skills/_local/`.

---

## Skill scope policy (canonical)

Three tiers, one rule per tier:

### Tier 1 — `skills/` (tracked, shipped with every install)

Skills that belong here satisfy **all** of the following:

- Universal and stack-agnostic — a Ruby dev and a Go dev both benefit equally
- About workflow method, not technology choice — `do-work`, `tdd`, `atomic-commits`, `grill-me`, `write-a-prd`
- Maintained by repo maintainer(s) — not third-party authored content
- Adds no framework dependency or credential requirement

**Examples that belong:** `do-work`, `tdd`, `atomic-commits`, `grill-me`, `write-a-prd`, `prd-to-issues`, `skill-scaffolder`, `explore`, `research`, `systematic-debugging`, `codebase-audit`, `improve-architecture`, `technical-fellow`

**Examples that do not belong:** Prisma ORM expert, Vercel React optimization, Sanity schema design, any SEO tooling, any client-specific workflow

### Tier 2 — `skills/_local/` (gitignored, never shipped)

Private skills that belong to the user, not the repo. These are auto-discovered by all runtimes at session start alongside Tier 1 skills.

- Business-specific logic, client voice/tone, proprietary workflows
- Personal productivity preferences
- Stack-specific skills (Prisma, Next.js, Laravel, etc.)
- Third-party vendor skills migrated from external installers

`_local/` is gitignored in `.gitignore` and will never be committed.

### Tier 3 — Fork-level additions

Skills intended for contribution must pass the Tier 1 test. If a skill is domain-specific (ad copywriting, SEO citation building, Sanity CMS workflows), the correct destination is:

- `examples/<use-case>/` — for demonstrating ctrl+shft applied to a specific domain
- Not `skills/` — skills/ is not an extension point for domain expertise

---

## Migration for existing users

Users who cloned before this ADR was written may have `skills/_vendor/` populated on their machine. The migration path is:

1. `rm -rf ~/dotfiles/skills/_vendor/` — remove the vendored directory from dotfiles
2. Skills that were previously in `_vendor/` can be moved to `~/dotfiles/skills/_local/vendor/` to preserve access without polluting the tracked tree
3. Run `bash ~/dotfiles/bin/bootstrap.sh` — this will re-sync consumer directories from the updated source

`bootstrap.sh` will be updated to print a migration notice if `skills/_vendor/` is detected on an existing clone.

---

## Consequences

**Positive:**
- `skills/` remains a clean, curated set of universal workflow methods
- New users get a fast, predictable install with no personal-taste surprises
- Skill count in the tracked repo is honest (13–14 core skills, not 20 inflated by vendor packs)
- validate-symlinks.sh and CI checks apply to a smaller, well-defined surface

**Negative:**
- Users who relied on vendored skills (Prisma expert, Vercel React, etc.) need to re-add them manually to `_local/`
- External agent framework skill installers (`~/.agents/`) will drift again unless the user maintains their own `_local/` discipline

**Neutral:**
- `bootstrap.sh` steps 6 and 7 (`.copilot/skills` and `.agents/skills` symlinks) remain — they still point to `~/dotfiles/skills/`, which now contains only Tier 1 skills plus the user's `_local/`

---

## Alternatives considered

**Path B — keep `_vendor/` behind opt-in installer:** Rejected. An opt-in mechanism requires documentation, maintenance, and a decision point at install time. The net value is low relative to the complexity added. Users who want specific third-party skills know how to install them via the originating framework.

**Keep `_vendor/` and gitignore its contents:** Rejected. Empty tracked directories with gitignored contents create silent machine-to-machine drift, the exact failure mode this project was built to prevent.

---

## ADR Note

This ADR requires no external approval at this stage. It should be revisited when the first external contributor submits a skill PR, to validate that the Tier 1 acceptance criteria are clear enough to gate contributions without ambiguity.
