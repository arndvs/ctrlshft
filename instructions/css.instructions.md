---
description: "CSS and styling conventions — Tailwind, design tokens, responsive patterns, and frontend UI rules."
---
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

Define all colors as CSS custom properties in `globals.css` `:root` / `.dark` blocks. Never use hardcoded hex/rgb values — always use design tokens.

### Semantic Tokens

- **Core:** `background`, `foreground`, `primary`, `secondary`, `accent`, `destructive`, `muted`
- **Paired:** each has a `-foreground` variant (e.g. `primary-foreground` for text on `primary` bg)
- **Interactive:** `border`, `input`, `ring`
- **Containers:** `card`, `popover` (each with `-foreground`)

## Dark Mode

- Use `next-themes` with class-based `.dark` selector. Re-declare tokens in `.dark {}`.
- Do NOT add manual `dark:` variants — use the token system and they swap automatically

## Component Patterns

- Use `cn(baseClasses, className)` for all className composition — never string concatenation
- Use `cva()` for components with multiple visual variants (see `button.tsx`, `badge.tsx`)
- Use `data-slot='component-name'` on component root elements
- shadcn/ui components use `React.ComponentProps<>` (not `forwardRef`)
- Minimum touch target: `min-h-[44px]` on all interactive elements
- Use `asChild` via Radix `Slot` when a component needs to render as a different element

## Forms

- `react-hook-form` + `zod` + `@hookform/resolvers` for validation
- `aria-invalid={!!error}` + `aria-describedby` for error association
- Error messages use `role="alert"`

## Images

- Sanity images via `urlForImage()` with `.auto('format').fit('max')`
- Use `next/image` with `fill` + `object-cover` for hero/featured images
- Always specify `sizes` prop
- Use `priority` on logo and hero images

## Accessibility

- `aria-hidden="true"` on decorative elements (icons, background effects)
- `sr-only` for visually hidden but screen-reader-accessible text
- Semantic landmarks: `<header>`, `<main>`, `<footer>`, `<nav>`, `<address>`
- `focus-visible:` ring utilities on interactive elements
- `print:hidden` on header/nav elements

## Rules

- Do not use top borders as visual separators
- No decorative borders except on native DOM elements (input, textarea)
- If using borders on focus/hover/selected states, add an invisible border to the default state to prevent layout shift
- Before using any CSS variable, class, or Tailwind token, verify it actually exists in the codebase. Search for its definition first — never assume a name exists based on convention or naming patterns
- When reorganizing or moving elements, check and fix spacing
- When I upload an image for you, describe it with pixel perfect accuracy and aim to replicate it perfectly as close to the image as possible
- Use Tailwind utility classes directly — avoid custom CSS unless defining `@theme` tokens, `@keyframes`, or `@utility` rules
- Use shadcn/ui components for interactive elements — do not build custom accessible widgets from scratch
- When shadcn/ui doesn't have the component, use Radix UI primitives directly
- Prefer `data-[state=open]:`, `data-[disabled]:` attribute selectors over pseudo-class variants with Radix components
- Never hardcode colors — always use design tokens

</css>
