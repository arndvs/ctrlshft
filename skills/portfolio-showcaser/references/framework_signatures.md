# Framework Signatures

How `code_analyzer.py` identifies frameworks, and what `feature_discovery.py`
uses for route enumeration.

## Detection Priority

Frameworks are checked in this order. First match wins (with `also_requires`
guard for disambiguation).

| Framework | Config Files | Dependency | Also Requires |
|-----------|-------------|------------|---------------|
| Next.js | `next.config.{js,mjs,ts}` | `next` | — |
| Nuxt | `nuxt.config.{js,ts}` | `nuxt` | — |
| SvelteKit | `svelte.config.{js,ts}` | `svelte`, `@sveltejs/kit` | — |
| Vite + React | `vite.config.{js,ts,mjs}` | `vite` | `react` |
| Vite + Vue | `vite.config.{js,ts,mjs}` | `vite` | `vue` |
| CRA | — | `react-scripts` | — |
| Angular | `angular.json` | `@angular/core` | — |
| Remix | `remix.config.{js,ts}` | `@remix-run/react` | — |
| Astro | `astro.config.{mjs,ts}` | `astro` | — |
| Gatsby | `gatsby-config.{js,ts}` | `gatsby` | — |
| Django | `manage.py` | `django` | — |
| Flask | — | `flask` | — |
| Rails | `Gemfile`, `Rakefile` | — | — |
| Laravel | `artisan` | `laravel/framework` | — |
| HTML | `index.html` | — | — |

## Route Discovery per Framework

### Next.js (App Router)
- Pages: `app/**/page.{tsx,jsx,ts,js}`
- Layouts: `app/**/layout.{tsx,jsx}`
- API Routes: `app/api/**/route.{ts,js}`
- Route Groups: directories starting with `(`
- Dynamic routes: directories with `[param]`
- Parallel routes: directories starting with `@`

### Next.js (Pages Router)
- Pages: `pages/**/*.{tsx,jsx,ts,js}` (excluding `_app`, `_document`)
- API Routes: `pages/api/**/*.{ts,js}`

### Vite + React (React Router)
- Search `App.tsx`, `routes.tsx`, `router.tsx` for `path=` patterns

### Nuxt
- Pages: `pages/**/*.vue`
- Dynamic: `[param].vue` directories

### SvelteKit
- Pages: `src/routes/**/+page.svelte`
- Dynamic: `[param]` directories

### Astro
- Pages: `src/pages/**/*.{astro,md,mdx}`

### Static HTML
- Pages: `*.html` in root directory

## Package Manager Detection

| Lockfile | Manager |
|----------|---------|
| `pnpm-lock.yaml` | pnpm |
| `bun.lockb` or `bun.lock` | bun |
| `yarn.lock` | yarn |
| `package-lock.json` | npm |
| (fallback) | npm |

## Port Defaults

| Framework | Default Port |
|-----------|-------------|
| Next.js | 3000 |
| CRA | 3000 |
| Remix | 3000 |
| Nuxt | 3000 |
| Vite | 5173 |
| SvelteKit | 5173 |
| Angular | 4200 |
| Astro | 4321 |
| Django | 8000 |
| Gatsby | 8000 |
| Flask | 5000 |

Port can be overridden in framework config files. The analyzer checks
`next.config.{js,mjs,ts}` and `vite.config.{js,ts,mjs}` for explicit
`port` settings.
