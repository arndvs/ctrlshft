# Exploration Playbook

Step-by-step instructions for the VS Code agent during the exploration phase.

## Before You Start

1. The orchestrator has already:
   - Analyzed the codebase (framework, integrations, patterns)
   - Discovered and scored features
   - Started the dev server (unless `--skip-server`)
   - Initialized state and screenshot directories

2. You receive:
   - A sorted list of features with routes and scores
   - A focus mode (core, interactions, responsive, edge_cases, performance, freestyle)
   - A base URL (usually `http://localhost:3000`)

## Core Exploration Workflow

For each feature in the exploration plan:

### Step 1: Navigate
```
Navigate to {base_url}{route}
Wait for network idle (no pending requests for 500ms)
```

### Step 2: Assess
```
Look at the page. Ask yourself:
- Is this visually impressive?
- Is there something technically interesting visible?
- Would this look good in a portfolio?
```

### Step 3: Capture
```
Take screenshots using the screenshot manager.
Use step names from STEP_ORDER (see screenshot_manager.py):
  overview, hero_section, navigation, feature_detail,
  form_interaction, form_validation, modal_or_drawer,
  loading_state, empty_state, error_state,
  responsive_mobile, responsive_tablet, responsive_desktop,
  animation, hover_effect, dark_mode, search, data_table,
  chart_or_visualization, auth_flow, checkout_flow, misc
```

### Step 4: Annotate
```
For each screenshot, write a brief annotation:
- What makes this notable
- What technical pattern it demonstrates
- What you'd say about it in an interview
```

### Step 5: Update State
```
Mark the feature as 'screenshotted' in state_store.
Add any code highlights you discover.
```

## Focus Mode Checklists

### Core (default)
- [ ] Full-page overview screenshot
- [ ] Hero/header section close-up
- [ ] Navigation menu
- [ ] Most visually impressive section
- [ ] Note design system consistency

### Interactions
- [ ] Find a form, fill with test data
- [ ] Submit invalid data for validation
- [ ] Open modals/drawers/dropdowns
- [ ] Trigger hover effects
- [ ] Spot-check animations/transitions
- [ ] Try keyboard navigation

### Responsive
- [ ] Mobile (375×812): full page + menu
- [ ] Tablet (768×1024): full page
- [ ] Desktop (1440×900): full page
- [ ] Compare navigation across breakpoints
- [ ] Check for horizontal scroll at mobile

### Edge Cases
- [ ] Capture loading/skeleton states
- [ ] Visit non-existent route for 404
- [ ] Submit empty form for validation
- [ ] Look for empty states (no data)
- [ ] Check error boundaries

### Performance
- [ ] Note largest contentful paint element
- [ ] Watch for layout shifts on load
- [ ] Check lazy loading on scroll
- [ ] Time page transitions
- [ ] Look for FOUT/FOIT on fonts

### Freestyle
- [ ] Explore as a curious user
- [ ] Try unexpected interactions
- [ ] Look for dark mode
- [ ] Test search functionality
- [ ] Check data tables for sorting/filtering
- [ ] Maximum 5 screenshots of best finds

## Screenshot Quality Guidelines

1. **Full page > cropped**: Capture the full viewport for context
2. **Before/after pairs**: Show interactions (form empty → filled → submitted)
3. **Annotate everything**: Future-you won't remember what was notable
4. **Skip duplicates**: Don't screenshot identical-looking pages
5. **Budget**: Stay within `screenshot_budget` from config (default 5 per feature)

## When Things Go Wrong

### Page returns 404
- Check if the route requires authentication
- Try the route with/without trailing slash
- Skip and note as observation

### Page loads but is blank
- Wait longer (some SPAs take time)
- Check browser console for errors
- Note as potential SSR/hydration issue

### Server crashes mid-exploration
- The circuit breaker will trip after 5 consecutive failures
- Restart the run; it resumes from last completed feature
- Try `--skip-server` and start the server manually

### Feature requires auth
- Note it as a flow to explore separately
- Check if there's a seed/demo user in the project
- Look for `.env.example` for test credentials
