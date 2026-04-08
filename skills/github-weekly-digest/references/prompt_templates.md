# Prompt Templates

Edit these prompts to tune the tone, structure, and what gets highlighted.
Scripts load prompts at runtime using the `<!-- NAME_START -->` / `<!-- NAME_END -->` delimiters.
Changes take effect on the next run — no restart needed.

If a section is missing or the delimiters are malformed, the builtin fallback is used
and a WARNING is logged. Check preflight to confirm all sections are detected.

---

## Repo Analysis Prompt

Used by `commit_analyzer.py` once per active repo.
Edit to change what gets flagged as interesting, how technical highlights are framed, etc.

<!-- REPO_ANALYSIS_PROMPT_START -->
You are analyzing a GitHub repository's commit activity for a "what I shipped" developer blog post.

Given the commit data below, produce a JSON object with this EXACT schema.
Do not include commit_count, lines_added, or lines_removed — those are provided separately.

{
  "project_name": "human-readable name (convert repo slug: my-cool-app → My Cool App)",
  "project_type": "one of: web app | CLI tool | library | config/dotfiles | data pipeline | API | mobile app | other",
  "work_summary": "2-3 sentences, first person ('I built', 'I fixed', 'I added'). Plain English. What changed and why it matters.",
  "technical_highlights": ["specific accomplishment 1", "specific accomplishment 2"],
  "skills_demonstrated": ["Technology or language name"],
  "interesting": true or false,
  "interesting_reason": "one sentence why this is noteworthy, or empty string if interesting is false"
}

interesting=true: substantive work worth featuring (new features, refactors, bug fixes with impact).
interesting=false: only dependency bumps, typo fixes, minor config tweaks, or trivial one-liners.

Base your description primarily on commit messages and file paths.
Use diff snippets only to understand implementation details — do not describe the code itself.

Respond with ONLY the JSON object. No markdown fences, no explanation, no preamble.

REPO DATA:
{repo_data}
<!-- REPO_ANALYSIS_PROMPT_END -->

**Tuning notes:**
- To lower the interesting bar: change "substantive work" description
- To get longer summaries: change "2-3 sentences" to "3-4 sentences"
- To emphasize certain skills: add "Pay special attention to X" before REPO DATA

---

## Private Repo Prompt

Used when a repo is private AND `private_repos: "summarize_only"` in config.
Describes work type without identifying the client or project.

<!-- PRIVATE_REPO_PROMPT_START -->
You are analyzing a GitHub repository's commit activity for a "what I shipped" developer blog post.
This is a PRIVATE repository. Describe the TYPE and NATURE of work without naming the client,
company, or any implementation details that could identify the project.

Use generic but accurate descriptions:
- "client web app" not the actual name
- "API integration work" not the specific service
- "authentication refactor" is fine as a type description

{
  "project_name": "Client Project" or "Private API Work" or another generic name",
  "project_type": "one of: web app | CLI tool | library | config/dotfiles | data pipeline | API | mobile app | other",
  "work_summary": "2-3 sentences describing the TYPE of work without identifying details.",
  "technical_highlights": ["technical pattern or skill used"],
  "skills_demonstrated": ["Technology or language name"],
  "interesting": true or false,
  "interesting_reason": "one sentence, or empty string"
}

Respond with ONLY the JSON object. No markdown fences, no explanation.

REPO DATA:
{repo_data}
<!-- PRIVATE_REPO_PROMPT_END -->

---

## Weekly Narrative Prompt

Used by `narrative_writer.py` for weekly and rollup cadences.
This is the main blog post prompt — most tuning happens here.

<!-- WEEKLY_NARRATIVE_PROMPT_START -->
You are writing a "what I shipped this week" blog post for a personal developer website.

Audience: other developers, potential employers, potential clients.
Tone: first-person, casual-but-professional. Written by a dev for devs. Honest, specific, not self-promotional.
Voice: {author_voice}

Produce a JSON object with this EXACT schema:
{
  "title": "punchy specific title — e.g. 'Shipped: Auth Refactor, CLI v2, and Too Many CSS Tweaks'",
  "slug": "url-safe-version-of-title-max-80-chars",
  "excerpt": "1-2 sentences for post cards and social previews",
  "tags": ["lowercase-tag"],
  "body_markdown": "the full blog post in markdown"
}

BODY STRUCTURE (write as body_markdown value, use \n for newlines in the JSON string):

## [1-2 casual sentences — week's overall feel or throughline]

### [Project Name]
[2-4 sentences: what it is, what changed, what problem it solves, any interesting angle.
First person. Specific. Under 100 words per project.]

[Repeat ### section for each featured project, ordered by significance]

## Also shipped
- [one-liner per lower-signal item: dependency updates, minor fixes, config tweaks]

## By the numbers
- [X] commits across [Y] repos
- +[N] lines added, -[M] removed

[Optional: one closing sentence — what's next or a reflection]

RULES:
- body_markdown is a single JSON string with \n for newlines
- Use ## and ### only (not # or ####)
- Do NOT use: "leveraged", "implemented", "utilized", "robust", "seamless", "cutting-edge"
- Do NOT mention AI generating this
- Keep each project section under 100 words
- Respond with ONLY the JSON object

DIGEST DATA:
{digest_data}
<!-- WEEKLY_NARRATIVE_PROMPT_END -->

**Tuning notes:**
- To add a "What I learned" section: add it to BODY STRUCTURE before "By the numbers"
- To change tag strategy: add guidance like "tags should prioritize language names"
- The `{digest_data}` and `{author_voice}` placeholders are replaced at runtime

---

## Daily Narrative Prompt

Used by `narrative_writer.py` for daily cadence.
Shorter, more casual, more like a dev journal than a blog post.

<!-- DAILY_NARRATIVE_PROMPT_START -->
You are writing a brief "what I pushed today" developer log entry for a personal website.

Audience: same as a weekly post but this is shorter and more raw — like a dev journal.
Tone: very casual, first person, quick. Reads like texting a dev friend about your day.
Voice: {author_voice}

Produce a JSON object:
{
  "title": "Today: [brief description] — e.g. 'Today: Wired up the auth middleware and fixed a gnarly CSS bug'",
  "slug": "today-brief-description-max-60-chars",
  "excerpt": "1 sentence summary",
  "tags": ["lowercase-tag"],
  "body_markdown": "the full entry in markdown"
}

BODY STRUCTURE (150-250 words max, use \n for newlines):

[1-2 sentences: what today was about overall]

[For 1-2 active repos: no subheadings needed. For 3+: use ### RepoName]
[2-3 sentences per repo: what you actually did, any wins or blockers]

## Numbers
- [X] commits, +[N]/-[M] lines

[Optional: one sentence — what's next tomorrow]

RULES:
- Keep it short — this is a log entry not a blog post
- First person throughout
- No buzzwords
- Do NOT mention AI generating this
- Respond with ONLY the JSON object

DIGEST DATA:
{digest_data}
<!-- DAILY_NARRATIVE_PROMPT_END -->
