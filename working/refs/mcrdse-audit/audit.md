# MCRDSE Repo Audit — Severity Assessment

Date: 2026-08-05
Scope: all repos under `~/dev/clients/mcrdse/`
Method: structural survey (file counts, line counts, largest files, layout/component adoption, stack detection). No code was modified.

---

## Executive summary

The MCRDSE portfolio is **six repos, four different stacks, all sharing the same disease**: monolithic files, near-zero layout/component reuse, and duplicated markup. The two flagship Astro sites (`mcrdse-site`, `mcrdsemovement-site`) are the worst offenders — pages of 1,000–2,900 lines each, with a single layout that isn't even adopted by most pages. This is exactly the "3000-line page" problem from the earlier Astro discussion, now confirmed at scale across the portfolio.

**Headline numbers:**

| Repo | Stack | src files | Astro files | src lines | Worst file |
|------|-------|-----------|-------------|-----------|------------|
| `mcrdse-site` | Astro 6 + Cloudflare | 174 | 47 | 39,912 | `shop/[slug].astro` 2,869 |
| `mcrdsemovement-site` | Astro 6 + MDX + Preact | 126 | 48 | 22,094 | `layouts/Base.astro` 1,425 |
| `mcrdse-ops` | Astro 5 + Cloudflare | 153 | 24 | 24,599 | `pages/index.astro` 1,524 |
| `mcrdse-super-market` | Static HTML (no framework) | 18 html | — | 4,820 | `cart.html` 1,365 |
| `MCRDSE-Content-Ship` | Cloudflare Worker (TS) | 36 | — | 10,653 | — |
| `mcrdse-outreach` | Python scripts + markdown | — | — | 13,067 | `reddit_campaign.py` 18k |

**Verdict: the problem is real and severe.** Three of six repos are actively being developed with monolithic Astro pages that violate DRY at scale. The other three are smaller but have their own hygiene issues (static HTML duplication, untyped worker code, loose scripts). A nightly backlog loop is justified — but it must be **stack-aware**, because a single Astro-only skill (the current `astro-files` draft) covers only half the portfolio.

---

## Per-repo findings

### 1. `mcrdse-site` — CRITICAL (flagship, actively developed)

- **Stack:** Astro 6.4 + `@astrojs/cloudflare` v13 (already migrated to Workers), Tailwind v4, Vitest, Resend.
- **Structure:** 29 pages, 17 components, **1 layout**. 39,912 lines of src.
- **Monolithic pages:**
  - `src/pages/shop/[slug].astro` — **2,869 lines**
  - `src/pages/index.astro` — **2,627 lines**
  - `src/pages/cart.astro` — **1,503 lines**
  - `src/pages/account.astro` — **1,148 lines**
- **Problems:**
  - 4 pages over 1,000 lines; the 300-line ceiling is exceeded by ~10x.
  - 1 layout for 29 pages → most pages almost certainly re-implement page chrome or skip it.
  - 17 components for 29 pages is low; expect heavy inline duplication.
  - `src/pages/api/`, `src/pages/go/`, `src/pages/order/`, `src/pages/relay-p8k3n/`, `src/pages/shop/` subfolders suggest route sprawl.
  - Has `src/workers/` and `src/lib/_generated/` — mixed concerns in one tree.
- **Priority:** **P0.** This is the main site and the largest debt. Start here.

### 2. `mcrdsemovement-site` — HIGH

- **Stack:** Astro 6.1 + MDX + Preact + Pagefind + Sitemap. **Still on Pages** (`wrangler pages deploy`).
- **Structure:** 32 pages, 15 components, 1 layout. 22,094 lines.
- **Monolithic files:**
  - `src/layouts/Base.astro` — **1,425 lines** (a layout this big is itself a monolith)
  - `src/pages/quiz/[archetype].astro` — **1,084 lines**
  - `src/pages/microdosing-legal-tracker.astro` — **856 lines**
  - `src/pages/mycelium/creators.astro` — **733 lines**
- **Problems:**
  - The single layout is 1,425 lines — the "extract the layout" win is inverted; the layout needs decomposition.
  - 8 content collections exist (`member-stories`, `mycelium`, `pillar-landings`, `practice`, `root`, `science`, `site-pages`, `what-we-reject`) — good, but pages still carry 700–1,000 lines each.
  - Still on Pages; the Workers migration (from the earlier discussion) hasn't landed here.
- **Priority:** **P1.** Second-largest Astro debt; also needs the Pages→Workers migration.

### 3. `mcrdse-ops` — HIGH

- **Stack:** Astro 5.18 + `@astrojs/cloudflare` v12 (older adapter — pre-v13, still Pages-era API).
- **Structure:** 20 pages, **2 components**, 2 layouts. 24,599 lines.
- **Monolithic files:**
  - `src/pages/index.astro` — **1,524 lines**
  - `src/pages/analytics.astro` — **1,113 lines**
  - `src/pages/affiliates.astro` — **660 lines**
- **Problems:**
  - **2 components for 20 pages** — the worst component-to-page ratio in the portfolio. Massive duplication expected.
  - 24,599 lines across only 24 Astro files → ~1,025 lines/file average.
  - Adapter is v12 (pre-v13); needs the same Workers migration as the others.
- **Priority:** **P1.**

### 4. `mcrdse-super-market` — MEDIUM

- **Stack:** **Static HTML, no framework.** 18 top-level `.html` files, 4,820 lines. Wrangler Pages static deploy.
- **Problems:**
  - `cart.html` 1,365 lines, `marketplace-home.html` 739, `product-detail.html` 578 — hand-written static HTML with no templating.
  - No shared header/footer partial — every page duplicates chrome.
  - `data/`, `assets/`, `docs/` present; `scripts/` for product sync.
- **Priority:** **P2.** Lower urgency (static, smaller), but the DRY violation is total — every page re-implements the shell.

### 5. `MCRDSE-Content-Ship` — MEDIUM

- **Stack:** Cloudflare Worker (TypeScript), D1, scripts library + teleprompter. 10,653 TS lines.
- **Problems:**
  - 24 worker files + 12 scripts; `worker/` + `scripts/` split.
  - No `src/` — code lives at repo root in `worker/` and `scripts/`.
  - Has migrations, tests, vitest — better hygiene than the Astro repos, but untyped/loose script layer.
- **Priority:** **P2.** Healthiest of the non-Astro repos; mostly needs structure/typing tightening.

### 6. `mcrdse-outreach` — LOW/MEDIUM

- **Stack:** Python scripts + markdown runbooks. 10,324 py lines + 2,743 md.
- **Problems:**
  - `reddit_campaign.py` 18k bytes, `reddit_cron.py`, `reddit_discover.py` at repo root (not in a package).
  - `gohighlevel-cli/`, `reddit-campaign/`, `reactivation-emails/`, `winback-emails/` — loose folders.
  - No `package.json` (Python). Runbooks are markdown.
- **Priority:** **P3.** Lowest urgency; scripts are operational, not a product surface.

---

## Cross-cutting themes

1. **Monolithic files everywhere.** 8+ files over 700 lines across the Astro repos. The 300-line ceiling is the norm-breaker, not the exception.
2. **Layout/component starvation.** 1 layout for 29 pages (`mcrdse-site`), 2 components for 20 pages (`mcrdse-ops`). The "extract the layout" and "extract components" phases are the highest-leverage work in every repo.
3. **DRY violations at scale.** Duplicated nav/footer/card markup is near-certain given the component ratios. The audit script's duplicate-block detector will quantify this on first run.
4. **Mixed stacks.** Four stacks across six repos. **A single Astro-only skill cannot serve the portfolio.** The skill must detect stack and dispatch to a stack-appropriate audit.
5. **Two repos still on Pages.** `mcrdsemovement-site` (v6, Pages) and `mcrdse-ops` (v12 adapter) predate the v13 Workers-only adapter. Migration is a prerequisite for `mcrdse-site`-style Workers deployment.
6. **No visual regression coverage.** None of the repos have screenshot baselines. For refactors of this size, that's the difference between a clean week and a nightmare — Phase 0 must establish baselines.

---

## Recommended remediation priority

| Order | Repo | Why |
|-------|------|-----|
| 1 | `mcrdse-site` | Flagship, largest debt, already on Workers (no migration blocker) |
| 2 | `mcrdsemovement-site` | Second-largest; needs Pages→Workers first |
| 3 | `mcrdse-ops` | High debt; needs adapter upgrade first |
| 4 | `mcrdse-super-market` | Static; cheap wins via templating |
| 5 | `MCRDSE-Content-Ship` | Healthier; structure/typing tightening |
| 6 | `mcrdse-outreach` | Operational scripts; lowest urgency |

---

## What this means for the automation

The nightly backlog loop must be:

- **Stack-aware** — detect Astro vs static-HTML vs Worker-TS vs Python, and run the matching audit + phase model.
- **Per-repo** — one workflow per repo (or a matrix), each with its own ledger and phase state. A shared ledger across repos would let one repo's phase block another's.
- **Gated on the open-issue check** — one open task per repo max, exactly as the `astro-files` draft designs.
- **Phase-ordered within each repo** — safety net → layout → components → styling → content → ratchet, per stack.

The `astro-files` draft is a solid single-repo, single-stack implementation. The work is to **generalize it into a `repo-hygiene` skill** that dispatches by stack, and to **wire a nightly workflow per repo** that creates one backlog issue each night.
