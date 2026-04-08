# Setup Guide

## 1. Python Venv

```bash
python -m venv ~/dotfiles/secrets/.venv
source ~/dotfiles/secrets/.venv/bin/activate   # Linux/Mac
# Windows: ~/dotfiles/secrets/.venv/Scripts/activate

pip install PyGithub anthropic requests
```

Always activate before running:
```bash
source ~/dotfiles/secrets/.venv/bin/activate
```

---

## 2. .gitignore (do this first)

```bash
cp assets/.gitignore .gitignore
```

This prevents `config.json` (which holds your API tokens) from being committed.

---

## 3. GitHub Personal Access Token

1. GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens
2. **Required permissions:** `repo` (Contents: Read-only) — enough to read commits and diffs
3. Set expiration (90 days recommended — calendar-remind yourself to rotate)
4. Copy `ghp_...` into `config.json` → `github_token`

**Org repos:** If you commit to repos under a GitHub org, add the org name to `include_orgs: ["org-name"]`. You'll need the token to have access to that org.

**Private repos:** Control visibility with `private_repos`:
- `"include"` — all private repos appear in digest (default)
- `"skip"` — private repos fetched but excluded entirely
- `"summarize_only"` — private repos analyzed but AI describes work type without naming client/project

---

## 4. Anthropic API Key

1. console.anthropic.com → API Keys → Create
2. Copy `sk-ant-...` into `config.json` → `anthropic_api_key`

**Model options** (set in `ai_model`):
- `claude-sonnet-4-6` — best balance of quality and cost (default)
- `claude-opus-4-6` — highest quality, ~5× more expensive
- `claude-haiku-4-5-20251001` — fastest and cheapest, good for dailies

Token usage and estimated cost are logged on every run.

---

## 5. Sanity CMS

### 5a. Add schema types

Copy `assets/sanity_schema.js` into your Sanity project:

```js
// schema/index.js or sanity.config.js
import { weeklyDigest, dailyDigest } from './digestSchemas'
export const schemaTypes = [...existingTypes, weeklyDigest, dailyDigest]
```

Deploy:
```bash
npx sanity deploy
```

### 5b. Create API token

Sanity manage → your project → API → Tokens → Add API token:
- Name: `digest-writer`
- Permissions: **Editor**

Copy into `config.json` → `sanity_token`.

### 5c. Find project ID and dataset

From your Sanity manage URL: `https://www.sanity.io/manage/personal/project/{PROJECT_ID}`
Dataset is usually `production`.

---

## 6. config.json

```bash
cp assets/config_template.json config.json
# Edit config.json — fill in all values
```

`config.json` is in `.gitignore` and must never be committed.

---

## 7. Pre-flight

```bash
python -m scripts.preflight --config config.json
```

All items must show ✓ before running.

---

## 8. First Run

```bash
# Dry run first — review output before publishing
python -m scripts.run_digest --config config.json --dry-run

# Review output/YYYY-MM-DD_post.md
# When satisfied:
python -m scripts.run_digest --config config.json

# Then review the draft in Sanity Studio and publish manually
```

---

## 9. Cron Schedule (Optional)

```bash
# Daily digest — every weekday at 7pm
0 19 * * 1-5 cd /path/to/digest && \
  source ~/dotfiles/secrets/.venv/bin/activate && \
  python -m scripts.run_digest --config config.json --cadence daily >> logs/daily.log 2>&1

# Weekly rollup — every Sunday at 9pm (synthesizes Mon-Fri dailies)
# --fill-gaps fetches any days where the daily was missed
0 21 * * 0 cd /path/to/digest && \
  source ~/dotfiles/secrets/.venv/bin/activate && \
  python -m scripts.run_digest --config config.json --cadence rollup --fill-gaps >> logs/weekly.log 2>&1
```

Create the logs dir: `mkdir -p logs`

---

## Downstream Skills

`output/YYYY-MM-DD_digest.json` is the shared data contract:
- LinkedIn post skill: reads digest.json, writes platform-optimized post
- Video script skill: reads digest.json, produces talking points
- Twitter/X thread skill: reads digest.json, produces thread

These are separate skills that take `--digest path/to/digest.json` as input.
