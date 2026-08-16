# Phases — Static HTML

For repos that are hand-written static `.html` files with no framework (e.g. `mcrdse-super-market`). The goal is to introduce a templating/shared-shell layer and eliminate per-page duplication. Walk in order; current phase is the first whose exit criteria are unmet.

---

## Phase 0 — Safety net

**Exit criteria**
- A build pipeline exists that renders the site from source (not hand-edited `dist`)
- Baseline rendered HTML is captured for every page
- CI runs the build on every PR
- `.refactor/state.json` exists and validates

**Task pool**
- Choose and wire a templating layer (see recipes): Astro, Eleventy, or a minimal Node render script. Astro is the natural choice if the portfolio is already Astro-heavy.
- Move the hand-written `.html` files into a `src/` tree as templates
- Add an HTML snapshot script that normalizes whitespace and hashes each page's output
- Add the CI workflow

**Note.** The single highest-leverage decision here is *which* templating layer. If the org standard is Astro, adopt Astro — it gives layouts, components, and content collections for free, and the rest of these phases become the Astro phase model. If the site must stay dependency-free, a minimal Node render script with a shared partial-include is the fallback.

---

## Phase 1 — Shared shell

**Exit criteria**
- A shared layout/partial owns `<html>`, `<head>`, header, nav, and footer
- ≥ 90% of pages use the shared shell
- Zero duplicated `<meta>`/favicon/font-link blocks across pages

**Task pool**
- Create the base layout from the most complete existing page's head + chrome
- Migrate pages to the layout in batches of ≤ 8, grouped by similarity
- Reconcile head divergence with named slots, not boolean props

---

## Phase 2 — Component extraction

**Exit criteria**
- No page exceeds 300 lines
- Zero duplicated markup blocks of ≥ 15 lines in ≥ 2 files
- Repeated cards/sections are components/partials
- Rendered HTML unchanged from the Phase 0 baseline

**Task pool**
- Extract a repeated block (nav, footer, card, product tile) into a partial/component, replacing every occurrence
- Split an oversized page into section partials — top-down, largest first
- Parameterize near-duplicates (differ only in text) into one component with props

---

## Phase 3 — Styling consolidation

**Exit criteria**
- A single global stylesheet holds the design tokens
- No inline `style=` attributes outside genuinely dynamic values
- Total custom CSS reduced by ≥ 80% from the Phase 0 measurement

**Task pool**
- Extract design tokens (colours, spacing, fonts) into CSS variables or a theme block
- Convert one component's inline styles to classes and delete the now-dead CSS
- Delete orphaned CSS rules

---

## Phase 4 — Content modelling

Applies only if structurally-identical pages differ only in content (e.g. product pages, landing pages).

**Exit criteria**
- Page families are data-driven (a data file + one template)
- No page duplicates another's structure with only content differences

**Task pool**
- Identify a page family and define its data schema
- Move the family's content into a data file (JSON/Markdown)
- Replace the family with one dynamic template + data loop

---

## Phase 5 — Ratchet

**Exit criteria**
- Lint rules enforce the constraints (max file length, no inline styles, no raw `<head>` in pages)
- Rules run in CI and fail the build
- README documents the layout/component conventions

**Task pool**
- Add file-length and inline-style lint rules
- Write the conventions doc
- Propose disabling the nightly cron

Once these are met the loop is finished. Say so and stop.
