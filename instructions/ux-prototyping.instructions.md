Output "Read UX Prototyping instructions." to chat to acknowledge you read this file.

# UX/UI Prototyping Guidelines

- Never change website copy unless told to

## Objective

Develop isolated components that developers can easily implement within a large headless CRM project. Each component should be self-contained with all utilities, Tailwind styles, and functionality in a single TSX file. Include JSON data at the top to populate text and images, facilitating future integration with a headless CMS. The caveat here is that if an external component data set is already being brought in, use that data set rather than refactoring the data set to then bring it into the component.

Be sure to review the Source Lib folder which contains hooks, styles, types, and utils for existing reusable functionality rather than creating from scratch. It's okay to create from scratch, however, if it already exists in the lib or any of this lib subdirectories, we should be using those pre-existing components rather than recreating new ones from scratch.

## File Naming Conventions

- Use kebab-case for all file names
  - ✅ `user-profile.tsx`, `auth-layout.tsx`, `api-utils.ts`
  - ❌ `userProfile.tsx`, `AuthLayout.tsx`, `apiUtils.ts`
- Use `.tsx` extension for React components
- Use `.ts` extension for utility files
- Use lowercase for all file names
- Separate words with hyphens
- Do not use spaces or underscores

## Dark Mode Requirements

**CRITICAL:** All components MUST support dark mode using the Dark Mode Design System (DMDS) tokens.

### Required Dark Mode Support

1. **Always include dark mode variants:**

   ```tsx
   // ✅ CORRECT
   <section className='bg-white dark:bg-surface-1'>

   // ❌ WRONG - Missing dark mode
   <section className='bg-white'>
   ```

2. **Use surface tokens, never hardcoded colors:**

   ```tsx
   // ✅ CORRECT
   <div className='bg-white dark:bg-surface-1'>
   <Card className='bg-card dark:bg-surface-2'>

   // ❌ WRONG - Hardcoded colors
   <div className='bg-white dark:bg-gray-900'>
   <Card className='bg-card dark:bg-slate-800'>
   ```

3. **Use semantic text tokens:**

   ```tsx
   // ✅ CORRECT
   <p className='text-foreground'>Primary text</p>
   <p className='text-muted-foreground'>Secondary text</p>

   // ❌ WRONG - Hardcoded colors
   <p className='dark:text-white'>Primary text</p>
   <p className='dark:text-gray-400'>Secondary text</p>
   ```

4. **Surface token decision matrix:**
   - Standard sections: `bg-white` → `dark:bg-surface-1`
   - Raised cards: `bg-card` → `dark:bg-surface-2`
   - Page background: `bg-background` → `dark:bg-surface-0` (handled globally)
   - Brand CTAs: `bg-primary/10` → `dark:bg-surface-accent`

### Reference Documentation

- **Complete guide:** `docs/dark-mode-design-system.md`
- **Token reference:** `src/lib/styles/dark-mode-tokens.ts`
- **Migration helpers:** `src/lib/utils/dark-mode-helpers.ts`

### Testing Requirements

- Test all components in both light and dark modes
- Verify WCAG AA contrast compliance
- Check for visual consistency across themes

## Component Structure Best Practices

### 1. DRY (Don't Repeat Yourself)

- Extract repeated logic into helper functions
- Create reusable UI elements for patterns that appear multiple times
- Use loops for rendering similar elements rather than duplicating JSX
- Maintain a single source of truth for data and configuration

### 2. Data Management

- Place all content data in a JSON object at the top of the file (unless a JSON object is already being imported into the file):

  ```tsx
  const componentData = {
    title: "Dashboard Overview",
    description: "View all your key metrics in one place",
    ctaText: "Explore Features",
    metrics: [
      { label: "Active Users", value: "5,234", icon: "users" },
      { label: "Conversion Rate", value: "3.2%", icon: "chart" },
    ],
    images: {
      hero: "/images/dashboard-hero.png",
      background: "/images/pattern-bg.svg",
    },
  };
  ```

- Separate data structure from presentation
- Include all text, labels, URLs, and image paths in this data object
- Use descriptive keys that align with their purpose in the UI

### 3. Component Organization

- Follow a logical structure:
  1. Data/configuration objects
  2. Helper functions/hooks
  3. Main component
  4. Subcomponents
- Export only the main component as default
- Keep subcomponents nested within the file scope

### 4. Props and TypeScript

- Define explicit TypeScript interfaces for all props:

  ```tsx
  interface ButtonProps {
    text: string;
    onClick: () => void;
    variant?: "primary" | "secondary" | "tertiary";
    isDisabled?: boolean;
  }
  ```

- Use discriminated unions for complex props
- Provide sensible defaults for optional props
- Use non-nullable types where appropriate

### 5. Tailwind Usage with shadcn Theme

- Use the defined color scheme from shadcn — CSS variables for colors instead of hardcoded Tailwind colors:

  ```tsx
  <div className="
      bg-background text-foreground
      border-border
      ring-ring
  ">
  ```

- Group related Tailwind classes together:

  ```tsx
  <div className="
      {/* Layout */}
      flex flex-col gap-4 p-6
      {/* Typography */}
      text-foreground font-medium
      {/* Visual */}
      bg-background rounded-lg shadow-md
      {/* States */}
      hover:shadow-lg transition-shadow duration-200
  ">
  ```

- Avoid arbitrary values (`[w-327px]`) when possible; use standard Tailwind spacing
- Use consistent shadcn color variables from the Tailwind config
- Implement responsive design using Tailwind breakpoints (`md:`, `lg:`)

### 6. shadcn Component Integration

- Import and use shadcn components for consistent UI:

  ```tsx
  import { Button } from "@/components/ui/button";
  import {
    Card,
    CardContent,
    CardHeader,
    CardTitle,
  } from "@/components/ui/card";
  import { Input } from "@/components/ui/input";
  ```

- Use shadcn variants for consistent styling:

  ```tsx
  <Button variant="default">Primary Action</Button>
  <Button variant="secondary">Secondary Action</Button>
  <Button variant="destructive">Delete</Button>
  ```

- Maintain shadcn's component prop structure
- Use shadcn's design tokens for spacing, typography, and colors
- Follow the dark mode rules in the **Required Dark Mode Support** section above

### 7. Server Components vs Client Components

**CRITICAL: Default to Server Components**

- **Use Server Components everywhere possible** — they are the default in Next.js App Router
- Server components render on the server, improving performance and reducing client-side JavaScript
- Only use Client Components (`'use client'`) when absolutely necessary

**When to Use Client Components:**

- Interactive elements requiring browser APIs (onClick, useState, useEffect)
- Components using Framer Motion animations (content sections only, not hero)
- Form inputs and interactive widgets
- Components that need to respond to user input in real-time

**Client Component Best Practices:**

- **Scope client components as small as possible** — only mark the minimal component that needs interactivity
- Extract interactive logic into the smallest possible client component
- Pass data down from server components as props
- Keep most of the component tree as server components

```tsx
// ✅ CORRECT - Server component with minimal client component
// Parent (Server Component)
export default function FeatureSection({ data }: Props) {
  return (
    <section>
      <h2>{data.title}</h2>
      <p>{data.description}</p>
      <InteractiveButton onClick={data.handleClick} />
    </section>
  );
}

// Child (Client Component - minimal scope)
("use client");
function InteractiveButton({ onClick }: { onClick: () => void }) {
  return <button onClick={onClick}>Click Me</button>;
}

// ❌ WRONG - Entire component marked as client when only button needs it
("use client");
export default function FeatureSection({ data }: Props) {
  return (
    <section>
      <h2>{data.title}</h2>
      <p>{data.description}</p>
      <button onClick={data.handleClick}>Click Me</button>
    </section>
  );
}
```

**Pattern for Data:**

- Server components fetch data directly
- Pass data to client components via props
- Never fetch data in client components

```tsx
// ✅ CORRECT - Server component fetches, client component receives
export default async function Page() {
  const data = await fetchData();
  return <InteractiveComponent data={data} />;
}

("use client");
function InteractiveComponent({ data }: { data: Data }) {
  const [state, setState] = useState();
  return <div>{/* Use data and state */}</div>;
}
```

### 8. Animation with Framer Motion

#### Modern Animation Philosophy

Our animation system prioritizes **instant content visibility** with **subtle, purposeful motion**:

- **Instant Initial Render**: Content appears immediately without animation delays
- **Subtle Motion**: Ultra-refined animations (4px movement, refined easing) for premium feel
- **Strategic Use**: Motion for interactions and meaningful feedback, not decoration
- **Performance First**: GPU-accelerated, CLS-safe, respects `prefers-reduced-motion`

**When to Animate:**

- ✅ Scroll-triggered content reveals (below the fold)
- ✅ Interactive feedback (hover, tap, focus)
- ✅ State changes (modals, dialogs, form states)
- ❌ Page-load animations (delays content visibility)
- ❌ Hero sections (must be server components, instant render)
- ❌ Above-fold content (use CLS-safe or instant variants)

- Use the existing `@animations.ts` variations rather than creating new animations from scratch
- Import and use Framer Motion as the primary animation library:

  ```tsx
  import { motion } from "framer-motion";
  ```

- **CRITICAL: Hero components MUST NOT use Framer Motion animations**
  - Hero sections should load immediately without animation delays
  - Hero components must be server components
  - Use only CSS transitions for hover states and subtle interactions

- **CRITICAL: Use scroll-triggered animations for content sections (non-hero)**

  ```tsx
  import {
    useContainerVariants,
    useItemVariants,
  } from "@/lib/hooks/use-animation-variants";

  const containerVars = useContainerVariants();
  const itemVars = useItemVariants();

  <motion.div
    initial="hidden"
    whileInView="visible"
    viewport={{ once: true, margin: "-100px" }}
    variants={containerVars}
  >
    {content}
  </motion.div>;
  ```

- **CRITICAL: Above-fold content MUST use CLS-safe or instant variants**

  ```tsx
  import { useItemVariants } from "@/lib/hooks/use-animation-variants";

  const variants = useItemVariants({ clsSafe: true });

  <motion.section
    initial="hidden"
    whileInView="visible"
    viewport={{ once: true, margin: "-100px" }}
    variants={variants}
  >
    Above-fold content
  </motion.section>;
  ```

- **Animation Patterns by Use Case:**

  **Hero Components (NO Framer Motion, Server Components Only):**

  ```tsx
  export default function HeroSection({ data }: Props) {
    return (
      <div className="hero-section">
        <h1>{data.title}</h1>
        <div className="transition-all hover:shadow-lg">
          {/* Only CSS transitions for hover states */}
        </div>
      </div>
    );
  }
  ```

  **Content Sections (use `whileInView`):**

  ```tsx
  import { useContainerVariants } from "@/lib/hooks/use-animation-variants";

  const containerVars = useContainerVariants();

  <motion.div
    initial="hidden"
    whileInView="visible"
    viewport={{ once: true, margin: "-100px" }}
    variants={containerVars}
  >
    {/* Page sections, cards, lists */}
  </motion.div>;
  ```

  **Interactive Elements (instant render + interaction-only):**

  ```tsx
  import { useInteractionVariants } from "@/lib/hooks/use-animation-variants";

  const buttonVars = useInteractionVariants("button");
  const microVars = useInteractionVariants("micro");

  <motion.button
    initial={{ opacity: 1 }}
    variants={buttonVars}
    whileHover="hover"
    whileTap="tap"
  >
    Click me
  </motion.button>;
  ```

  **Staggered lists:**

  ```tsx
  import {
    useContainerVariants,
    useItemVariants,
  } from "@/lib/hooks/use-animation-variants";

  const containerVars = useContainerVariants();
  const itemVars = useItemVariants();

  <motion.div
    initial="hidden"
    whileInView="visible"
    viewport={{ once: true, margin: "-50px" }}
    variants={containerVars}
  >
    {items.map((item) => (
      <motion.div key={item.id} variants={itemVars}>
        {/* Item content */}
      </motion.div>
    ))}
  </motion.div>;
  ```

- Use exit animations for elements being removed:

  ```tsx
  <AnimatePresence>
    {isVisible && (
      <motion.div
        initial={{ opacity: 0, height: 0 }}
        animate={{ opacity: 1, height: "auto" }}
        exit={{ opacity: 0, height: 0 }}
      >
        Content
      </motion.div>
    )}
  </AnimatePresence>
  ```

- **CRITICAL: Always respect user preferences for reduced motion:**

  ```tsx
  // ✅ REQUIRED - Use helper hooks (automatic accessibility)
  import {
    useContainerVariants,
    useInteractionVariants,
    useItemVariants,
  } from "@/lib/hooks/use-animation-variants";

  // Helper hooks automatically respect prefers-reduced-motion
  const containerVars = useContainerVariants();
  const itemVars = useItemVariants();
  const interactionVars = useInteractionVariants("button");
  ```

### 9. State Management

- Use appropriate React hooks for state:
  - `useState` for simple component state
  - `useReducer` for complex state logic
  - `useContext` for deeply nested component requirements
- Minimize state; derive values where possible
- Handle loading, error, and empty states explicitly

### 10. Accessibility Considerations

- Include proper ARIA attributes
- Ensure keyboard navigation works correctly
- Maintain sufficient color contrast (WCAG AA minimum)
- Use semantic HTML elements appropriately
- Implement proper focus management
- Ensure animations don't interfere with accessibility
- Always use helper hooks from `@/lib/hooks/use-animation-variants` for automatic accessibility support
- Above-fold content must use CLS-safe variants to prevent layout shift

### 11. Error Handling

- Implement graceful fallbacks for missing data
- Use conditional rendering to handle undefined states
- Add helpful error boundaries where appropriate
- Provide user-friendly error messages
- Use shadcn's Alert component for error states:

  ```tsx
  import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";

  <Alert variant="destructive">
    <AlertTitle>Error</AlertTitle>
    <AlertDescription>
      There was a problem loading your data. Please try again.
    </AlertDescription>
  </Alert>;
  ```

### 12. Performance Optimization

- Memoize expensive calculations with `useMemo`
- Prevent unnecessary re-renders with `useCallback` for handlers
- Optimize lists with proper `key` props
- Lazy-load offscreen or heavy components
- Use Framer Motion's LazyMotion for code-splitting animations:

  ```tsx
  import { LazyMotion, domAnimation, m } from "framer-motion";

  <LazyMotion features={domAnimation}>
    <m.div animate={{ scale: 1.2 }}>Lazy loaded animation</m.div>
  </LazyMotion>;
  ```

### 13. Component Documentation

- Add JSDoc comments describing the component's purpose:

  ```tsx
  /**
   * Dashboard card component that displays key metrics with icons.
   * Supports customization through the componentData object.
   * Uses shadcn components and Framer Motion animations.
   *
   * @example
   * <DashboardCard />
   */
  ```

- Document any complex logic with inline comments
- Include usage examples in comments
- Note any dependencies or requirements

### 14. Responsive Design

- Design mobile-first, then add responsive variants
- Use Tailwind breakpoints consistently
- Test on multiple viewport sizes
- Consider touch interactions for mobile devices

## Implementation Example

```tsx
// user-dashboard-card.tsx
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  useContainerVariants,
  useItemVariants,
} from "@/lib/hooks/use-animation-variants";
import { AnimatePresence, motion } from "framer-motion";

// ===== Component Data =====
const componentData = {
  title: "User Dashboard",
  subtitle: "Welcome back to your dashboard",
  metrics: [
    { id: "users", label: "Active Users", value: "5,234", trend: "+12%" },
    { id: "revenue", label: "Monthly Revenue", value: "$12,345", trend: "+8%" },
    {
      id: "conversion",
      label: "Conversion Rate",
      value: "3.2%",
      trend: "-0.5%",
    },
  ],
  cta: {
    text: "View Detailed Analytics",
    url: "/analytics",
  },
  images: {
    background: "/images/dashboard-bg.svg",
    avatar: "/images/user-avatar.png",
  },
};

// ===== Helper Functions =====
const formatTrend = (trend: string) => {
  const isPositive = trend.startsWith("+");

  return {
    value: trend,
    className: isPositive ? "text-green-500" : "text-red-500",
    icon: isPositive ? "↑" : "↓",
  };
};

// ===== Component =====
const UserDashboardCard: React.FC = () => {
  const containerVars = useContainerVariants();
  const itemVars = useItemVariants();

  return (
    <motion.div
      initial="hidden"
      whileInView="visible"
      viewport={{ once: true, margin: "-100px" }}
      variants={containerVars}
    >
      <Card className="mx-auto max-w-2xl overflow-hidden">
        <CardHeader className="bg-card text-card-foreground">
          <CardTitle>{componentData.title}</CardTitle>
          <p className="text-muted-foreground">{componentData.subtitle}</p>
        </CardHeader>

        <CardContent className="p-6">
          <motion.div
            className="grid grid-cols-1 gap-4 md:grid-cols-3"
            variants={containerVars}
          >
            {componentData.metrics.map((metric) => (
              <MetricCard key={metric.id} {...metric} />
            ))}
          </motion.div>

          <motion.div className="mt-8" variants={itemVars}>
            <Button variant="default" asChild>
              <a href={componentData.cta.url}>{componentData.cta.text}</a>
            </Button>
          </motion.div>
        </CardContent>
      </Card>
    </motion.div>
  );
};

// ===== Subcomponents =====
interface MetricProps {
  id: string;
  label: string;
  value: string;
  trend: string;
}

const MetricCard: React.FC<MetricProps> = ({ label, value, trend }) => {
  const trendData = formatTrend(trend);
  const itemVars = useItemVariants();

  return (
    <motion.div
      variants={itemVars}
      whileHover={{ scale: 1.03, transition: { duration: 0.2 } }}
      className="bg-secondary border-border flex flex-col rounded-lg border p-4"
    >
      <span className="text-muted-foreground text-sm">{label}</span>
      <span className="text-foreground mt-1 text-2xl font-bold">{value}</span>
      <span className={`mt-2 flex items-center text-sm ${trendData.className}`}>
        {trendData.icon} {trendData.value}
      </span>
    </motion.div>
  );
};

export default UserDashboardCard;
```
