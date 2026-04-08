---
name: github-weekly-digest
description: Automated "what I shipped" pipeline. Pulls commit history from all personal GitHub repos, uses AI to analyze the work, and publishes narrative blog posts to Sanity CMS. Supports three cadences: daily (brief dev log), weekly (full "what I shipped" post), and rollup (weekly post synthesized from saved daily files — no extra GitHub API calls). Use this skill whenever the user wants to generate a weekly dev digest, daily commit log, summarize GitHub commits, create a "what I shipped" post, publish to Sanity from GitHub activity, review coding work, or produce commit-based content. Triggers on: "weekly digest", "daily digest", "what I shipped", "commit summary", "GitHub recap", "weekly roundup", "publish commits to Sanity", "blog post from commits", "dev update", "rollup".
---

# GitHub Digest

Automated pipeline: GitHub commits → AI analysis → narrative blog post → Sanity CMS draft.

**Three cadences:**
- **daily** — brief "what I pushed today" dev log, posted as `dailyDigest`
- **weekly** — full "what I shipped this week" post, posted as `weeklyDigest`
- **rollup** — weekly post synthesized from saved daily JSON files (zero GitHub API calls)

---

## First-Time Setup

```bash
# 1. Activate venv
source ~/dotfiles/secrets/.venv/bin/activate
pip install PyGithub anthropic requests

# 2. Configure non-sensitive settings
cp assets/config_template.json config.json
# Edit config.json — fill in github_username, ai_model, digest preferences

# 3. Add tokens to secrets/.env.secrets (process-scoped, never in shell)
# GITHUB_TOKEN=ghp_...
# ANTHROPIC_API_KEY=sk-ant-...
# SANITY_TOKEN=sk...
# See ~/dotfiles/.env.secrets.example for the full list

# 4. Add non-sensitive Sanity config to secrets/.env.agent
# SANITY_PROJECT_ID=your-project-id
# SANITY_DATASET=production

# 5. Add Sanity schema types (weeklyDigest + dailyDigest)
# Copy assets/sanity_schema.js to your Sanity project, import both exports, deploy:
#   npx sanity deploy

# 6. Pre-flight (must run via run-with-secrets.sh to inject tokens)
~/dotfiles/bin/run-with-secrets.sh python -m scripts.preflight --config config.json
```

See `references/setup.md` for full token setup, org repo config, and private repo handling.

---

## File Structure

```
github-weekly-digest/
├── SKILL.md
├── config.json                      ← create from assets/config_template.json
├── .gitignore                       ← copy from assets/.gitignore (do this first)
├── assets/
│   ├── config_template.json
│   ├── sanity_schema.js             ← weeklyDigest + dailyDigest types
│   └── .gitignore                   ← copy to project root
├── references/
│   ├── setup.md
│   ├── prompt_templates.md          ← edit to tune AI tone and structure
│   └── troubleshooting.md
└── scripts/
    ├── __init__.py
    ├── shared_utils.py              ← config, dates, logging, token tracking, merging
    ├── github_fetcher.py            ← GitHub API: repos + commits + diffs
    ├── commit_analyzer.py           ← per-repo AI analysis
    ├── narrative_writer.py          ← blog post generation (all three cadences)
    ├── sanity_publisher.py          ← Sanity CMS draft creation
    ├── preflight.py                 ← validate all config + API connections
    └── run_digest.py                ← main orchestrator (entry point)
```

---

## Running

All commands must be run via `run-with-secrets.sh` to inject API tokens:

```bash
source ~/dotfiles/secrets/.venv/bin/activate  # always activate first
alias digest='~/dotfiles/bin/run-with-secrets.sh python -m scripts.run_digest --config config.json'

# Weekly (default)
digest

# Daily
digest --cadence daily

# Weekly rollup from saved daily files
digest --cadence rollup

# Rollup + fetch any missing days from GitHub
digest --cadence rollup --fill-gaps

# Dry run (analyze, save files, don't publish)
digest --dry-run

# Custom date range
digest --since 2025-01-06 --until 2025-01-12

# Single repo (for testing)
digest --repo my-project

# Reuse saved analysis (skip AI re-analysis after a crash)
digest --reuse-analysis

# Force overwrite existing Sanity draft
digest --force

# Pre-flight only
~/dotfiles/bin/run-with-secrets.sh python -m scripts.preflight --config config.json
```

---

## Pipeline Phases

### Phase 1 — Fetch GitHub Activity (`github_fetcher.py`)

- Fetches all repos for `github_username` (plus any `include_orgs`)
- Per repo: all commits in the window (author match, merge commits skipped)
- Per commit: file paths, lines added/removed, diff patches from most-changed files
- Lock files and minified assets excluded from diffs automatically
- Repos sorted by lines changed descending — most active first
- Rate limit protection: auto-pauses if < 50 requests remaining

**Private repo control** (`private_repos` config key):
- `"include"` — all private repos in digest
- `"skip"` — private repos excluded entirely
- `"summarize_only"` — private repos analyzed with a privacy-preserving prompt (describes work type, not client/project details)

### Phase 2 — Per-Repo AI Analysis (`commit_analyzer.py`)

One Claude API call per active repo. Input: commit messages, file paths, diff from most-changed commit. Output: structured JSON with project name, type, summary, highlights, skills, and whether it's interesting enough to feature.

**Commit/line counts always come from real fetched data — never from AI.**

Prompts loaded at runtime from `references/prompt_templates.md` using `<!-- SECTION_START/END -->` delimiters. Edit there to tune behavior. Falls back to builtin with a logged warning if file/section missing.

Token usage logged per call and summed for the run.

### Phase 3 — Narrative Generation (`narrative_writer.py`)

One Claude API call for the full post. Different prompt per cadence:
- **weekly/rollup** — full blog post with project sections, "also shipped", stats
- **daily** — short dev log entry, 150-250 words

`week_of` field always snapped to the Monday of the week. Raw response saved to disk on JSON parse failure so the user can recover manually.

### Phase 4 — Sanity Publish (`sanity_publisher.py`)

- `createIfNotExists` by default — **won't overwrite manual Sanity Studio edits**
- `--force` switches to `createOrReplace`
- Always creates as **draft** — human reviews and publishes in Sanity Studio
- Daily cadence → `dailyDigest` document type
- Weekly/rollup → `weeklyDigest` document type
- Rollup weekly post includes `dailyRefs[]` linking back to daily draft docs

### Rollup Path (`run_digest.py` `_run_rollup`)

Reads saved `{date}_analysis.json` files from `output/` for each day Mon–Sun. Merges per-repo (sums stats, unions skills/highlights, interesting=true if any day was interesting). Feeds merged analyses to narrative writer as a single weekly post. No GitHub API calls unless `--fill-gaps` is passed.

---

## config.json

```json
{
  "github_username": "your-username",
  "github_token": "ghp_...",
  "excluded_repos": [],
  "skip_forks": false,
  "include_orgs": [],
  "max_diff_files": 20,
  "private_repos": "include",

  "anthropic_api_key": "sk-ant-...",
  "ai_model": "claude-sonnet-4-6",

  "sanity_project_id": "abc123",
  "sanity_dataset": "production",
  "sanity_token": "sk...",
  "sanity_api_version": "2024-01-01",

  "digest": {
    "default_days": 7,
    "author_name": "Your Name",
    "author_voice": "casual dev writing for other devs and potential clients"
  },

  "output": {
    "json_output_dir": "./output/",
    "retain_days": 90
  }
}
```

---

## Output Files

Each run saves to `output/` (files older than `retain_days` are auto-deleted):

| File | Content |
|------|---------|
| `YYYY-MM-DD_analysis.json` | Per-repo AI analysis (used by rollup + `--reuse-analysis`) |
| `YYYY-MM-DD_post.md` | Rendered blog post for review |
| `YYYY-MM-DD_digest.json` | Full structured data — shared contract for downstream skills |
| `YYYY-MM-DD_narrative_raw.txt` | Raw AI response, created only on parse failure |

**`digest.json` is the data contract** for downstream channel skills (LinkedIn, video script, Twitter thread). Its schema is stable across cadences.

---

## Cron Schedule

```bash
# Daily — every weekday at 7pm
0 19 * * 1-5 cd /path/to/digest && \
  source ~/dotfiles/secrets/.venv/bin/activate && \
  python -m scripts.run_digest --config config.json --cadence daily >> logs/daily.log 2>&1

# Weekly rollup — every Sunday at 9pm
0 21 * * 0 cd /path/to/digest && \
  source ~/dotfiles/secrets/.venv/bin/activate && \
  python -m scripts.run_digest --config config.json --cadence rollup --fill-gaps >> logs/weekly.log 2>&1
```

---

## Audit Fix Summary (v1 → v2)

All 21 issues from the code audit addressed:

| # | Issue | Fix |
|---|-------|-----|
| 1 | Rate limit datetime TypeError | `datetime.now(timezone.utc)` everywhere; `total_seconds()` for delta |
| 2 | Prompt loaded at import, silent fallback | Loaded at call time; warning logged on fallback |
| 3 | No error handling on narrative call | try/except with raw response salvage to disk |
| 4 | Timezone mutation bug in `get_date_window` | All `.replace()` calls include `tzinfo=timezone.utc` |
| 5 | `%-d` breaks Windows | `{since.day}` directly, no strftime format code |
| 6 | Fragile backtick prompt parsing | Comment delimiter system `<!-- NAME_START/END -->` |
| 7 | `createOrReplace` silently overwrites edits | `createIfNotExists` default; `--force` flag to override |
| 8 | AI returns stats that override real counts | Stats schema removed from AI prompt; always use fetched values |
| 9 | `get_repos` misses org repos | `include_orgs` config + org repo fetching |
| 10 | Diffs from first commit, not most significant | `most_changed_commit` property; diff from max lines-changed commit |
| 11 | Dead import in `run_digest.py` | Removed |
| 12 | `week_of` not snapped to Monday | `monday_of_week()` util used in `narrative_writer.py` |
| 13 | No `.gitignore` | `assets/.gitignore` created; preflight warns if missing |
| 14 | Tokens logged at DEBUG level | Third-party loggers suppressed at WARNING in `get_logger()` |
| 15 | O(commits) API calls undocumented | Documented in troubleshooting.md |
| 16 | No token usage logging | `TokenUsage` dataclass; logged per call and as run summary |
| 17 | Private repos exposed | `private_repos` config: include/skip/summarize_only |
| 18 | AI describes code from tiny diff fragments | Lock files excluded; diff sorted by lines changed; prompt clarifies diffs are supplementary |
| 19 | Output files accumulate forever | `retain_days` config + `cleanup_old_outputs()` |
| 20 | `_key()` UUID truncation | Full 32-char UUID, no truncation |
| 21 | No idempotency / reuse-analysis | `--reuse-analysis` flag; rollup reads saved daily JSON files |

---

## Reference Files

- `references/setup.md` — full token setup, org config, private repo, Sanity schema, cron
- `references/prompt_templates.md` — edit AI prompts here; takes effect immediately
- `references/troubleshooting.md` — rate limits, parse errors, Sanity issues, rollup gaps
