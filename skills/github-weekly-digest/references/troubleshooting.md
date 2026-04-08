# Troubleshooting

## GitHub API

**"401 Unauthorized"**
Token expired or wrong. Regenerate at GitHub → Settings → Developer settings.

**"No commits found" for a busy week**
- Date window issue: `--since`/`--until` use local date strings but comparison is UTC. If you're UTC-8, commits after 4pm may fall on the next UTC day.
- Try widening: `--since 2025-01-05 --until 2025-01-13`
- GitHub uses committer date, not author date — rebased commits may shift.

**Rate limit hit**
The fetcher auto-pauses. Each repo needs roughly: 1 call (list commits) + 1 per commit (fetch files). 10 repos × 5 commits = ~60 API calls. Authenticated limit: 5,000/hour.

Use `--repo specific-repo` to test against a single repo before a full run.

**Org repos not appearing**
Add the org to `include_orgs: ["org-name"]` in config.json and ensure your token has access.

**Forks you don't want**
Set `skip_forks: true` in config.json, or add repo names to `excluded_repos`.

---

## AI Analysis

**JSON parse error on a repo**
The model occasionally wraps output in code fences. The code strips these automatically. If it still fails, the repo is skipped with an error log. Re-run with `--repo that-repo-name` to retry just that one.

**All repos marked interesting=false**
Edit `references/prompt_templates.md` → Repo Analysis Prompt. Loosen the `interesting=false` description.

**Stats in blog post are wrong**
Stats now always come from real fetched data — AI never provides these. If they look wrong, check the raw `_analysis.json` file.

**Prompt changes not taking effect**
Check that `<!-- SECTION_NAME_START -->` and `<!-- SECTION_NAME_END -->` delimiters are intact in `prompt_templates.md`. Run preflight to verify detection.

---

## Narrative / Blog Post

**JSON parse failed — narrative_raw.txt created**
The raw Claude response was saved to `output/YYYY-MM-DD_narrative_raw.txt`. Open it, copy the JSON object, paste into a validator, fix any issues, and manually create the post in Sanity Studio.

**Generic title ("Shipped: Week of January 6, 2025")**
Happens when all repos are `interesting=false`. Lower the interesting threshold in the Repo Analysis Prompt.

**Post too long / too short**
Edit `WEEKLY_NARRATIVE_PROMPT` in `prompt_templates.md`. Adjust "Under 100 words per project" or the overall structure.

---

## Sanity

**"403 Forbidden"**
Token lacks Editor permissions. Regenerate at Sanity manage → API → Tokens.

**"Schema type not found"**
Deploy schema first: `npx sanity deploy` in your Sanity project directory.

**Draft already exists (no changes made)**
By design: `createIfNotExists` won't overwrite manual edits. To force overwrite: `--force`.

**Body appears empty in Studio**
Markdown-to-Portable-Text handles `##`/`###` headings, paragraphs, and bullet lists.
Tables, code blocks, bold/italic inline are not converted.
Check `output/YYYY-MM-DD_post.md` — if content is there, the issue is in conversion.

---

## Rollup

**Missing daily files**
Run with `--fill-gaps` to fetch missing days from GitHub automatically.

**Rollup covers wrong week**
Rollup defaults to last Monday–Sunday. Override with `--since 2025-01-06 --until 2025-01-12`.

**Daily files from wrong output dir**
Rollup reads from the same `output.json_output_dir` as daily runs. Make sure both use the same config.

---

## Output / Cleanup

**Output dir growing large**
Set `output.retain_days: 90` in config.json. Files older than 90 days are deleted after each successful run.

**Cron job produces no output**
- Ensure venv is activated in the cron command
- Use absolute paths
- Redirect stderr: `>> logs/digest.log 2>&1`
- Cron doesn't inherit shell env vars — token env vars must be in the cron command or a sourced file
