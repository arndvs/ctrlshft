# Recipes

Mechanics for each phase's task types. Read the section for the current phase before writing the task. The Astro sections carry the most detail; the stack-specific sections note where the mechanics differ.

## Layout extraction (Astro, Phase 1)

Pick the *most complete* head block as the source, not the most common one — it's easier to make a rich layout optional than to discover a missing meta tag three weeks later.

```astro
---
// src/layouts/BaseLayout.astro
interface Props {
  title: string;
  description?: string;
  ogImage?: string;
}
const { title, description, ogImage } = Astro.props;
---
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width" />
    <title>{title}</title>
    {description && <meta name="description" content={description} />}
    <slot name="head" />
  </head>
  <body>
    <SiteHeader />
    <slot />
    <SiteFooter />
  </body>
</html>
```

**Divergence goes in slots, not props.** When six pages agree and one has an extra script, `<slot name="head" />` absorbs it. A `hasAnalytics` boolean prop starts a pattern that ends with fourteen booleans and an unreadable layout.

**`is:inline` scripts don't get bundled.** If a page has one in its head, moving it into the layout changes when it runs relative to other scripts. Move these individually and check the page still works, rather than sweeping them up in a batch.

**Migrate in similarity groups.** Diff the head blocks first and batch pages whose heads are identical. Mixed batches produce PRs where every file needs individual review.

## Component extraction (Astro, Phase 2)

The invariant: rendered HTML byte-identical modulo whitespace. Everything else follows from that.

Order of operations for one extraction:
1. Copy the canonical block verbatim into the new component file
2. Identify what varies across occurrences → those become props
3. Replace **every** occurrence in the same commit
4. Build, verify HTML hashes unchanged
5. Only then, if the component's markup is obviously wrong, open a *separate* issue

That step 5 discipline is the whole game. The moment structural extraction and improvement mix, the diff stops being reviewable and the HTML-unchanged check stops being usable.

**Props vs slots:**
- Data → props (`title`, `items`, `variant`)
- Markup → slots
- Passing an HTML string as a prop means it should have been a slot
- More than ~6 props usually means two components

**Near-duplicates.** Blocks that differ in text but not structure become one component with props. Blocks that differ in structure stay separate until Phase 2 is otherwise done — forcing them together early produces a component full of conditionals that's harder to read than the duplication was.

**Splitting a giant page.** Go top-down by visual section (hero, features, testimonials, CTA), not bottom-up by small repeated elements. Section components immediately shrink the page file; button components don't.

## Tailwind conversion (Astro, Phase 3)

**Wiring** (v4 — the `@astrojs/tailwind` integration is legacy):

```js
// astro.config.mjs
import tailwindcss from "@tailwindcss/vite";
export default defineConfig({
  vite: { plugins: [tailwindcss()] },
});
```

```css
/* src/styles/global.css */
@import "tailwindcss";

@theme {
  --color-brand: #1a4d8f;
  --font-display: "Söhne", sans-serif;
}
```

**Extract tokens before converting anything.** Grep the existing CSS for every distinct colour, spacing value, font stack, and breakpoint. Put the real values in `@theme`. If you convert components first, each conversion invents its own approximation of `#1a4d8f` and you end up with nine near-identical blues.

**Convert-and-delete is one task.** The CSS rules a component exclusively owned get deleted in the same PR that adds its utility classes. Otherwise the stylesheet never shrinks and both systems stay live indefinitely — this is how Tailwind migrations stall.

**Keep scoped `<style>` for:** keyframes, complex grid templates, anything genuinely local and intricate. Astro scopes these already; they aren't automatically debt. Convert the layout, spacing, colour, and typography utilities.

**`@reference` in scoped blocks.** Using `@apply` inside an Astro `<style>` block needs `@reference "../styles/global.css";` at the top, or the theme values won't resolve. Common source of silent breakage.

**Orphan sweep.** After each conversion batch, look for selectors that no longer match anything. These accumulate fast and deleting them is where the 80% reduction actually comes from.

## Content collections (Astro, Phase 4)

Applies when N pages share structure and differ only in content.

```ts
// src/content.config.ts
import { defineCollection, z } from "astro:content";
const posts = defineCollection({
  schema: z.object({
    title: z.string(),
    date: z.coerce.date(),
    draft: z.boolean().default(false),
  }),
});
export const collections = { posts };
```

Then one dynamic route with `getStaticPaths` replaces the whole family.

**Preserve URLs.** If the existing pages are indexed, the slugs must match exactly or add redirects. Check the route inventory from Phase 0 before and after — a silent URL change is the one mistake in this whole refactor that costs real traffic.

## Ratchet rules (Phase 5)

Lint rules worth enforcing, roughly in order of value:
- Max lines per file in `src/pages/` (set it just above your current worst file, then lower it over time)
- No raw `<html>`/`<head>` in `src/pages/`
- No inline `style=` with static values
- `interface Props` required in components taking props

Setting the threshold just above current-worst and ratcheting down is what makes this stick. A rule everyone has to disable on day one gets deleted on day two.

---

## Static HTML (Phases 1–2)

**Choosing the templating layer (Phase 0).** If the org standard is Astro, adopt Astro — the static-HTML phases then collapse into the Astro phases. If the site must stay dependency-free, use a minimal Node render script:

```js
// scripts/render.mjs — reads src/pages/*.html, injects a shared shell
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
const shell = readFileSync("src/_shell.html", "utf8");
// ... replace {{content}} and {{title}} placeholders, write to dist/
```

**Shared shell (Phase 1).** The static-HTML equivalent of a layout is a `_shell.html` partial with `{{content}}`/`{{title}}` placeholders, or an Astro `BaseLayout`. Migrate pages in similarity batches.

**Component extraction (Phase 2).** Repeated nav/footer/card markup becomes either an Astro component or a partial-include. The invariant is the same: rendered HTML byte-identical modulo whitespace.

## Worker TS (Phases 1–2)

**Structure (Phase 1).** Establish `src/handlers/`, `src/services/`, `src/lib/`, `src/types/`. The entry point (`src/index.ts` or `worker.ts`) should only wire routes to handlers:

```ts
// src/index.ts — thin
import { handleShop } from "./handlers/shop.js";
export default { fetch: (req, env, ctx) => route(req, env, ctx) };
```

**DRY extraction (Phase 2).** Extract response wrappers, auth checks, and validation into `src/lib/`. The invariant for a worker is: same inputs → same outputs, verified by the test suite, not HTML hashes.

## Python (Phases 1–2)

**Package structure (Phase 1).** Move root scripts into a package and make CLI entry points thin:

```python
# src/mcrdse_outreach/cli.py — thin wrapper
from .reddit import run_campaign
if __name__ == "__main__":
    run_campaign()
```

**DRY extraction (Phase 2).** Extract HTTP clients, auth, and config loading into shared modules. The invariant is verified by tests, not HTML hashes.
