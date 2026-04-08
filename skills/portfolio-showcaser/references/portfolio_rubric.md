# Portfolio Scoring Rubric

How `highlight_scorer.py` ranks features for portfolio impact.

## Four-Axis Rubric

Each feature is scored 1-5 on four axes with different weights:

| Axis | Weight | What It Measures |
|------|--------|-----------------|
| **Visual** | 1.0× | How visually interesting/impressive is this feature? |
| **Technical** | 1.2× | How technically sophisticated is the implementation? |
| **Uniqueness** | 1.5× | How non-boilerplate/unusual is this feature? |
| **Demonstrability** | 1.3× | Can this be meaningfully shown in screenshots? |

### Total Score Formula

```
total = (visual × 1.0) + (technical × 1.2) + (uniqueness × 1.5) + (demonstrability × 1.3) + bonus + penalty
```

Maximum possible: `5×1.0 + 5×1.2 + 5×1.5 + 5×1.3 = 25.0` + bonuses

## Score Signals

### Visual Score (1-5)
- Base: 2
- +2 for user flows (auth, checkout, etc.)
- +1 for pages
- +1 for visual keywords (dashboard, chart, gallery, animation, hero)
- +1 for animation/visualization integrations

### Technical Score (1-5)
- Base: 2
- +1 for API endpoints
- +1 for flows
- +1 for tech keywords (api, webhook, auth, stream, search)
- +1 for tech integrations (AI, realtime, search, database, payments)
- +1 for advanced patterns (Server Actions, Parallel Routes, Streaming)

### Uniqueness Score (1-5)
- Base: 2
- -1 for generic pages (home, about, contact, login)
- +2 for unique keywords (AI, stripe, realtime, editor, playground)
- +1 for unique integrations (AI, realtime, search, visualization)
- +1 for checkout/onboarding flows

### Demonstrability Score (1-5)
- Base: 3
- +1 for pages and flows (easy to screenshot)
- -1 for API endpoints (hard to show visually)
- -1 for integrations (often invisible)
- +1 for interactive keywords (form, search, filter, editor)

## Bonuses

| Condition | Bonus |
|-----------|-------|
| Feature is a flow (auth, checkout, etc.) | +3.0 |
| Has loading.tsx or error.tsx sibling | +1.5 |
| Dynamic route (uses [param]) | +1.0 |
| API with multiple HTTP methods | +1.0 |

## Penalties

| Condition | Penalty |
|-----------|---------|
| Scaffold/boilerplate name (about, contact, 404, privacy, terms) | -2.0 |

## Example Scores

| Feature | V | T | U | D | Bonus | Total |
|---------|---|---|---|---|-------|-------|
| Checkout Flow (Stripe) | 4 | 4 | 4 | 4 | +4.0 | 28.0 |
| AI Chat Page | 3 | 5 | 5 | 4 | +1.0 | 23.7 |
| Dashboard w/ Charts | 5 | 3 | 3 | 5 | 0 | 20.1 |
| API /users (GET,POST) | 2 | 3 | 2 | 2 | +1.0 | 13.2 |
| About Page | 2 | 2 | 1 | 3 | -2.0 | 8.3 |

## Overriding Scores

The agent can manually adjust scores after exploration if:
- A feature turns out more impressive than static analysis predicted
- Screenshots reveal visual quality not detectable from file structure
- The feature has hidden technical depth (discovered during exploration)

Manual adjustments are recorded in `state.json` for reproducibility.
