Output "Read CSS instructions." to chat to acknowledge you read this file.

<css>

## Stack

- **Tailwind CSS v4** — CSS-first config via `@tailwindcss/postcss`, tokens defined in `globals.css` with `@theme inline`
- **shadcn/ui** (`https://ui.shadcn.com`, `new-york` style) for composable, accessible UI primitives — built on **Radix UI**
- **`cn()`** = `twMerge(clsx(...))` from `src/lib/utils.ts` for class composition
- **`cva`** (class-variance-authority) for multi-variant components (buttons, badges, cards)
- **Framer Motion** for scroll-triggered reveals and micro-interactions
- **lucide-react** for icons

## Color System

All colors use **OKLCH** color space, defined as CSS custom properties in `globals.css` `:root` / `.dark` blocks. Referenced in Tailwind via `hsl(var(--token))` in `tailwind.config.ts`. Never use hardcoded hex/rgb values.

### Semantic Tokens

- **Core:** `background`, `foreground`, `primary`, `secondary`, `accent`, `destructive`, `muted`
- **Paired:** each has a `-foreground` variant (e.g. `primary-foreground` for text on `primary` bg)
- **Interactive:** `border`, `input`, `ring`
- **Containers:** `card`, `popover` (each with `-foreground`)

### Surface Hierarchy (DMDS)

Four elevation levels — use these for section backgrounds, not raw colors:

- **`surface-0`** — page canvas (maps to `background`)
- **`surface-1`** — standard sections (maps to `card`)
- **`surface-2`** — raised cards, inset areas (maps to `muted`)
- **`surface-accent`** — brand-tinted CTAs (maps to `accent`)

### Brand Palette

- **`primary`** — mint green (`oklch(60.22% 0.106 184.89)`)
- **`secondary`** — gold (`oklch(0.75 0.18 85)`)
- **`peach`** — warm peach with `-foreground` variant
- **`wellness-cream`**, **`wellness-mint`**, **`wellness-sage`**, **`wellness-gold`** — wellness sub-palette

## Typography

- **`font-sans`** — Inter (body text, UI)
- **`font-display`** — Playfair Display (h1, h2, display headings)
- **`font-mono`** — Geist Mono (code blocks)
- Fonts loaded via `next/font/google` with `display: 'swap'` and CSS variable injection
- Custom tiny sizes: `text-tiniest` (0.4rem), `text-tinier` (0.5rem), `text-tiny` (0.625rem)

## Border Radius

Base `--radius: 0.625rem` (10px) with derived scale:

- `rounded-sm` = 6px, `rounded-md` = 8px, `rounded-lg` = 10px, `rounded-xl` = 14px

## Dark Mode

Handled via `next-themes` with class-based `.dark` selector. All OKLCH tokens are re-declared in `.dark {}`. Custom variant: `@custom-variant dark (&:is(.dark *))`.

- Do NOT add manual `dark:` variants — use the token system and they swap automatically
- Surface tokens have explicit dark values (`surface-0`: near-black, `surface-1`/`2`: progressively lighter)

## Layout

- **Container:** `mx-auto max-w-7xl px-4 sm:px-6 lg:px-8` — use the `Container` component or inline
- **Page wrapper:** `flex min-h-screen flex-col`
- **Section spacing:** `py-16 lg:py-24` is the standard section padding
- **Hero spacing:** varies per hero type — check the specific hero component
- **Grid patterns:** `grid grid-cols-1 gap-8 md:grid-cols-2 lg:grid-cols-3` for cards, `gap-16 lg:grid-cols-2` for asymmetric layouts
- Mobile-first with standard Tailwind breakpoints (`sm:`, `md:`, `lg:`, `xl:`)

## Animation

Framer Motion with a structured variant system in `src/lib/utils/animations.ts`:

- **Above-the-fold:** use `clsSafe` or `instant` variants (opacity only — no layout shift)
- **Below-the-fold:** use `containerVariants` / `itemVariants` with `whileInView="visible"` + `viewport={{ once: true, margin: '-50px' }}`
- **Stagger:** container `delayChildren` + `staggerChildren` (0.08s default)
- **Hover cards:** scale 1.01, y: -1 — no translate-only hover effects
- **Reduced motion:** always respected via `useReducedMotion()` — all hooks return `{ opacity: 1 }` fallback
- Use `useContainerVariants()` / `useItemVariants()` hooks — they auto-handle reduced motion

### Timing Scale

- Instant: 0s (critical content)
- Fast: 0.2s (hover, micro-interactions)
- Standard: 0.25s (most transitions)
- Slow: 0.4s (images, sparingly)

## Component Patterns

- Use `cn(baseClasses, className)` for all className composition — never string concatenation
- Use `cva()` for components with multiple visual variants (see `button.tsx`, `badge.tsx`)
- Use `data-slot='component-name'` on component root elements
- shadcn/ui components use `React.ComponentProps<>` (not `forwardRef`)
- Minimum touch target: `min-h-[44px]` on all interactive elements
- Use `asChild` via Radix `Slot` when a component needs to render as a different element

## Forms

- `react-hook-form` + `zod` + `@hookform/resolvers` for validation
- Wrap fields with `FormInputField` / `FormTextareaField` from `form-field.tsx`
- `aria-invalid={!!error}` + `aria-describedby` for error association
- Error messages use `role="alert"`
- Field layout: `space-y-6` for sections, `grid grid-cols-1 gap-4 sm:grid-cols-2` for field pairs

## Images

- All Sanity images via `urlForImage()` with `.auto('format').fit('max')`
- Use `next/image` with `fill` + `object-cover` for hero/featured images
- Always specify `sizes` prop
- Use `priority` on logo and hero images
- Aspect ratios: `16:9`, `4:3`, `1:1`, `21:9`, `3:2`, `9:16` from `AspectRatios` constants

## Accessibility

- `aria-hidden="true"` on decorative elements (icons, background effects, wave patterns)
- `sr-only` for visually hidden but screen-reader-accessible text
- Semantic landmarks: `<header>`, `<main>`, `<footer>`, `<nav>`, `<address>`
- `role="banner"` on hero sections, `role="contentinfo"` on footer
- `focus-visible:` ring utilities on interactive elements
- `print:hidden` on header/nav elements

## Rules

- Do not use top borders as visual separators
- No decorative borders except on native DOM elements (input, textarea)
- If using borders on focus/hover/selected states, add an invisible border to the default state to prevent layout shift
- Use Tailwind utility classes directly — avoid custom CSS unless defining `@theme` tokens, `@keyframes`, or `@utility` rules
- Use shadcn/ui components for interactive elements — do not build custom accessible widgets from scratch
- When shadcn/ui doesn't have the component, use Radix UI primitives directly
- Prefer `data-[state=open]:`, `data-[disabled]:` attribute selectors over pseudo-class variants with Radix components
- Never hardcode colors — always use design tokens
- Keep hero components as server components where possible (no animations = better SEO/performance)

</css>
