---
name: portfolio-showcaser
description: Automated portfolio-ready codebase analysis and exploration. Discovers standout features, scores them for portfolio impact, starts the dev server, guides agent-driven browser exploration, and generates a markdown report with annotated screenshots. Use when the user wants to showcase a project, generate a portfolio report, prepare for interviews, or find the most impressive features in a codebase. Triggers on: "showcase my project", "portfolio report", "highlight my best features", "what's impressive about this codebase", "prepare for interview", "screenshot my project", "portfolio analysis".
---

# Portfolio Showcaser Skill

Automated portfolio-ready codebase analysis and exploration. Discovers standout features, scores them for portfolio impact, starts the dev server, guides agent-driven browser exploration, and generates a markdown report with annotated screenshots.

## When to Use

Use this skill when the user wants to:
- Showcase a project for their portfolio
- Find the most impressive features in a codebase
- Generate a portfolio report from a local project
- Prepare for a job interview by identifying talking points
- Take annotated screenshots of their best work
- Understand what makes their project stand out

**Trigger phrases:** "showcase my project", "portfolio report", "highlight my best features", "what's impressive about this codebase", "prepare for interview", "screenshot my project", "portfolio analysis"

## Overview

The skill runs an 8-phase pipeline:

1. **Preflight** — Validate config, repo path, package manager, Node.js, port
2. **Analyze** — Static codebase analysis (framework, integrations, patterns, quality)
3. **Discover** — Enumerate pages, API endpoints, components, user flows
4. **Score** — Rank features using a 4-axis rubric (Visual, Technical, Uniqueness, Demonstrability)
5. **Init State** — Set up persistent JSON state store and output directories
6. **Start Server** — Install deps, start dev server, wait for ready
7. **Explore** — Agent-driven browser exploration with focus modes
8. **Report** — Generate markdown report and companion JSON data

## Quick Start

```bash
# 1. Copy and edit config
cp config.example.json config.json
# Edit config.json — set repo_path to your project

# 2. Dry run first (no server, no browser)
python -m scripts.run_showcase --config config.json --dry-run

# 3. Full run
python -m scripts.run_showcase --config config.json

# 4. Focus on specific aspects
python -m scripts.run_showcase --config config.json --focus interactions
```

## Configuration

Edit `config.json`:

```json
{
  "repo_path": "/absolute/path/to/your/project",
  "output_dir": "./output",
  "screenshots_dir": "./output/screenshots",
  "report_filename": "portfolio-report.md",
  "state_file": "./output/state.json",
  "exploration": {
    "max_features": 15,
    "screenshot_budget": 5,
    "viewports": {
      "mobile": { "width": 375, "height": 812 },
      "tablet": { "width": 768, "height": 1024 },
      "desktop": { "width": 1440, "height": 900 }
    },
    "dev_server_timeout": 120,
    "port": 3000
  },
  "session": {
    "circuit_breaker_threshold": 5
  }
}
```

Or override `repo_path` with `PORTFOLIO_REPO_PATH` environment variable.

## CLI Flags

| Flag | Description |
|------|-------------|
| `--config PATH` | Path to config.json (default: config.json) |
| `--focus MODE` | Exploration focus: core, interactions, responsive, edge_cases, performance, freestyle |
| `--feature NAME` | Explore a single feature by name |
| `--dry-run` | Analysis and scoring only — no server, no browser |
| `--skip-server` | Skip dep install and server start (useful if server already running) |

## Focus Modes

### core (default)
Full-page overview, hero section, navigation, most visually impressive section. Best for first run.

### interactions
Forms, modals, hover effects, animations, keyboard navigation. Best for showcasing UX polish.

### responsive
Same pages at mobile (375×812), tablet (768×1024), desktop (1440×900). Best for demonstrating responsive design.

### edge_cases
Loading states, error states, empty states, 404 handling. Best for showing production-readiness.

### performance
Loading behavior, LCP, layout shifts, lazy loading, font loading. Best for performance-conscious roles.

### freestyle
Agent explores freely, captures anything impressive. Best for finding hidden gems after a core run.

## Agent Exploration Instructions

During Phase 7, you control the browser. For each feature:

1. **Navigate** to the feature's route
2. **Wait** for the page to fully load (network idle)
3. **Read** the focus mode docstring in `exploration_engine.py` for specific actions
4. **Screenshot** using `screenshot_manager.screenshot_path(feature_name, step_name)`
5. **Annotate** each screenshot with `screenshot_manager.annotate(screenshot_path, annotation)`
6. **Update state** — the engine handles `set_status()` calls

### Screenshot Step Names

Use these ordered step names for consistent file naming:
`overview`, `hero_section`, `navigation`, `feature_detail`, `form_interaction`, `form_validation`, `modal_or_drawer`, `loading_state`, `empty_state`, `error_state`, `responsive_mobile`, `responsive_tablet`, `responsive_desktop`, `animation`, `hover_effect`, `dark_mode`, `search`, `data_table`, `chart_or_visualization`, `auth_flow`, `checkout_flow`, `misc`

## Scoring Rubric

Features are scored on four weighted axes:

| Axis | Weight | Measures |
|------|--------|----------|
| Visual | 1.0× | Visual impressiveness |
| Technical | 1.2× | Technical sophistication |
| Uniqueness | 1.5× | Non-boilerplate originality |
| Demonstrability | 1.3× | Can it be shown in screenshots? |

**Bonuses:** Flows (+3), loading/error siblings (+1.5), dynamic routes (+1), multi-method APIs (+1)
**Penalties:** Scaffold names like "about", "contact" (-2)

## Output Files

| File | Description |
|------|-------------|
| `output/portfolio-report.md` | Full report with scored features, tech stack, quality signals |
| `output/portfolio-data.json` | Structured JSON for programmatic use |
| `output/state.json` | Persistent state supporting resume |
| `output/screenshots/` | Annotated screenshots organized by session/feature |
| `output/session_logs/` | JSONL session logs for debugging |

## Supported Frameworks

Next.js (App/Pages Router), Nuxt, SvelteKit, Vite + React, Vite + Vue, CRA, Angular, Remix, Astro, Gatsby, Django, Flask, Rails, Laravel, static HTML.

## Error Handling

- **Circuit breaker**: Trips after 5 consecutive exploration failures, stops gracefully
- **Resume**: Re-run picks up from last completed feature via `state.json`
- **Server failure**: Falls back to `--skip-server` mode with warning
- **Missing deps**: Preflight catches and reports before running

## Reference Documents

- [setup.md](references/setup.md) — Installation and troubleshooting
- [framework_signatures.md](references/framework_signatures.md) — Framework detection details
- [portfolio_rubric.md](references/portfolio_rubric.md) — Full scoring formula and examples
- [exploration_playbook.md](references/exploration_playbook.md) — Detailed agent exploration instructions
