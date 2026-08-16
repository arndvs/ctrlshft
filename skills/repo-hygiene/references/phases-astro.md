# Phases — Astro

Walk these in order. The current phase is the **first** one whose exit criteria are unmet. Exit criteria are measured by `audit.mjs`, never asserted from memory.

Each phase lists a task pool. Pick one task from the current phase only.

---

## Phase 0 — Safety net

You cannot verify a behaviour-preserving refactor without a baseline. Everything downstream depends on this, so it goes first even though it produces no visible improvement.

**Exit criteria**
- `npm run build` and `npx astro check` both pass on a clean checkout
- A route inventory exists at `.refactor/routes.json` (every buildable URL)
- Baseline rendered HTML is captured for every route
- CI runs build + check on every PR
- `.refactor/state.json` exists and validates

**Task pool**
- Get the build green (fix errors only — no refactoring)
- Generate the route inventory from `dist/` after a build
- Add an HTML snapshot script that normalizes whitespace and hashes each route's output
- Add the CI workflow
- Optional but high value: Playwright screenshot baselines at 3 viewport widths

**Note on the snapshot approach.** Hashing normalized HTML is cheap and catches structural drift, which is exactly what Phases 1–2 risk. Screenshots catch styling drift, which is what Phase 3 risks. If the user only wants one, HTML hashing first — it's faster, has no browser dependency, and Phase 3 is further away.

---

## Phase 1 — Layout extraction

One base layout absorbing the shared page chrome. This is the single highest-leverage change in the whole refactor: it typically deletes 30–50% of total lines before a single component is written.

**Exit criteria**
- `src/layouts/BaseLayout.astro` exists and owns `<html>`, `<head>`, and the document shell
- ≥ 90% of files in `src/pages/` import a layout
- No file in `src/pages/` contains a raw `<html>` or `<head>` tag
- Zero duplicated `<meta>`/favicon/font-link blocks across pages

**Task pool**
- Create `BaseLayout.astro` from the most complete existing page head, with props for `title`, `description`, and `ogImage`, plus a default `<slot />`
- Migrate pages to the layout in batches of ≤ 8, grouped by similarity of their current head block
- Reconcile head divergence: where pages disagree (different meta, extra scripts), add a named slot rather than a boolean prop — slots keep the layout from accumulating conditionals
- Add secondary layouts only when a real second shape exists (e.g. a docs layout with a sidebar). Two layouts is fine. Six means props should have been used instead.

**Watch for.** Pages with `is:inline` scripts in the head, or `<style is:global>`. Both need to move deliberately — `is:inline` scripts are not bundled and their execution order relative to the layout matters.

---

## Phase 2 — Component extraction

Structure only. No visual change, no CSS touched. This is the phase most likely to go wrong through scope creep, so tasks here should be the tightest of any phase.

**Exit criteria**
- No file in `src/pages/` exceeds 300 lines
- Zero duplicated markup blocks of ≥ 15 lines appearing in ≥ 2 files
- `src/components/` exists with components averaging ≥ 2 importers
- Rendered HTML unchanged from the Phase 0 baseline

**Task pool**
- Extract a repeated block into a component, replacing every occurrence in the same PR (partial extraction leaves both versions to drift)
- Split one oversized page into section components — top-down, largest page first
- Parameterize near-duplicates: two blocks that differ only in text become one component with props
- Delete a component that ended up with one importer and no reuse prospect — over-extraction is real debt too

**Props vs slots.** Props for data (strings, arrays, booleans). Slots for markup. If you find yourself passing an HTML string as a prop, it should be a slot. If a component takes more than about 6 props, it's probably two components.

**Sizing.** One component per issue, or one page per issue. Not "extract the card, the badge, and the pagination."

---

## Phase 3 — Tailwind adoption

Only now, with markup stable and deduplicated, does styling conversion make sense. Converting earlier means converting the same block once per copy.

**Exit criteria**
- Tailwind v4 wired via `@tailwindcss/vite` in `astro.config`
- A single `src/styles/global.css` with `@import "tailwindcss"` and a `@theme` block holding the design tokens
- Total custom CSS reduced by ≥ 80% from the Phase 0 measurement
- No inline `style=` attributes outside genuinely dynamic values
- Screenshot diffs clean, or diffs explicitly reviewed and accepted

**Task pool**
- Install and wire Tailwind, coexisting with existing global CSS (converts nothing yet)
- Extract the design tokens: audit the existing CSS for its actual colour/spacing/font values and encode them in `@theme` — do this **before** converting any component, or every conversion invents its own approximations
- Convert one component's styles to utilities and delete the CSS rules it exclusively owned
- Delete orphaned CSS: rules whose selectors no longer match anything
- Replace ad-hoc breakpoints with the token scale

**The deletion rule.** A conversion task isn't done until the CSS it replaced is gone. Converting without deleting leaves both systems live and the stylesheet never shrinks — this is the most common way Tailwind migrations stall permanently.

**Scoped styles.** Astro's `<style>` blocks are already scoped and are not automatically debt. Keep them where the styling is genuinely local and complex (keyframes, grid templates). Convert the layout/spacing/colour utilities.

---

## Phase 4 — Content modelling

Applies only if the audit finds structurally-identical pages differing only in content. If it doesn't, skip to Phase 5.

**Exit criteria**
- Structurally identical page families are collections with schemas
- No page duplicates another's structure with only content differences
- Content schemas validate at build time

**Task pool**
- Identify a page family and define the collection schema
- Migrate the family's content into the collection
- Replace the page family with one dynamic route + `getStaticPaths`
- Move hardcoded data arrays out of `.astro` frontmatter into data files

---

## Phase 5 — Ratchet

Lock in the gains so the codebase can't slide back.

**Exit criteria**
- Lint rules enforce the constraints (max file length, no inline styles, no raw `<head>` in pages)
- Rules run in CI and fail the build
- README documents the component and layout conventions
- Type safety on component props

**Task pool**
- Add file-length and inline-style lint rules
- Type component props (`interface Props`)
- Write the conventions doc
- Add a11y and Lighthouse checks to CI
- Propose disabling the nightly cron

Once these are met the loop is finished. Say so and stop.
