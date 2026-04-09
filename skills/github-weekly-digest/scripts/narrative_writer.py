"""
narrative_writer.py — Generate the unified blog post via Claude API.

Supports three cadences:
  weekly — full "what I shipped this week" post
  daily  — brief "what I pushed today" dev log entry
  rollup — weekly post synthesized from merged daily analyses

Key fixes from audit:
- Full try/except with raw response salvage on parse failure
- week_of always snapped to Monday of the week
- Prompt loaded at call time with warning on fallback
- Token usage tracked
- author_voice from config injected into prompt
"""

import json
import re
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path

from scripts.commit_analyzer import RepoAnalysis
from scripts.shared_utils import (
    get_logger, week_label, day_label, iso_date,
    monday_of_week, TokenUsage, strip_fences,
)

log = get_logger("writer")

try:
    import anthropic
except ImportError:
    raise ImportError("anthropic package required. Install with: pip install anthropic")

_PROMPTS_PATH = Path(__file__).parent.parent / "references" / "prompt_templates.md"


@dataclass
class DigestPost:
    title: str
    slug: str
    cadence: str            # "daily" | "weekly" | "rollup"
    period_label: str       # "Week of Jan 6, 2025" or "Monday, Jan 6, 2025"
    week_of: str            # ISO date of Monday of the week (always a Monday)
    date: str               # ISO date of the day (for daily) or Monday (for weekly)
    excerpt: str
    body_markdown: str
    tags: list[str]
    stats: dict
    projects: list[dict]
    daily_refs: list[str]   # doc IDs of daily digests (for rollup weekly post)


def _load_prompt(section_name: str, builtin_fallback: str) -> str:
    start_tag = f"<!-- {section_name}_START -->"
    end_tag = f"<!-- {section_name}_END -->"
    if _PROMPTS_PATH.exists():
        content = _PROMPTS_PATH.read_text()
        start = content.find(start_tag)
        end = content.find(end_tag)
        if start != -1 and end != -1:
            extracted = content[start + len(start_tag):end].strip()
            if extracted:
                return extracted
    log.warning(
        f"Could not load '{section_name}' from prompt_templates.md. "
        f"Using builtin fallback."
    )
    return builtin_fallback


_BUILTIN_WEEKLY_PROMPT = """\
You are writing a "what I shipped this week" blog post for a personal developer website.

Audience: other developers, potential employers, potential clients.
Tone: first-person, casual-but-professional. Written by a dev for devs. Honest, specific.
Voice: {author_voice}

Produce a JSON object with this EXACT schema:
{
  "title": "punchy specific title — e.g. 'Shipped: Auth Refactor, CLI v2, and Too Many CSS Tweaks'",
  "slug": "url-safe-version-of-title-max-80-chars",
  "excerpt": "1-2 sentences for post cards and social previews",
  "tags": ["lowercase-tag"],
  "body_markdown": "the full blog post in markdown"
}

BODY STRUCTURE (write as body_markdown, use \\n for newlines in the JSON string):

## [1-2 casual sentences — week's overall feel or throughline]

### [Project Name]
[2-4 sentences: what it is, what changed, what problem it solves, any interesting angle.
First person. Specific. Under 100 words per project.]

[Repeat ### section for each featured project]

## Also shipped
- [one-liner for each lower-signal item: dependency updates, minor fixes, config tweaks]

## By the numbers
- [X] commits across [Y] repos
- +[N] lines added, -[M] removed
[add any other notable stat]

[Optional: one closing sentence — what's next or a brief reflection]

RULES:
- body_markdown is a single JSON string value with \\n for newlines
- Use ## and ### only (not # or ####)
- Do NOT use: "leveraged", "implemented", "utilized", "robust", "seamless"
- Do NOT mention AI generating this
- Respond with ONLY the JSON object

DIGEST DATA:
{digest_data}"""

_BUILTIN_ROLLUP_PROMPT = """\
You are writing a "what I shipped this week" blog post for a personal developer website.
This post is synthesized from MULTIPLE pre-analyzed daily snapshots — one per day the developer was active.

Your job is to weave a cohesive weekly narrative arc from these daily snapshots.
Show how the work evolved day by day. Connect threads across days.
Don't just list Monday's work then Tuesday's work — tell the story of the whole week.

Audience: other developers, potential employers, potential clients.
Tone: first-person, casual-but-professional. Written by a dev for devs. Honest, specific.
Voice: {author_voice}

Produce a JSON object with this EXACT schema:
{{
  "title": "punchy specific title — e.g. 'Shipped: Auth Refactor, CLI v2, and Too Many CSS Tweaks'",
  "slug": "url-safe-version-of-title-max-80-chars",
  "excerpt": "1-2 sentences for post cards and social previews",
  "tags": ["lowercase-tag"],
  "body_markdown": "the full blog post in markdown"
}}

BODY STRUCTURE (write as body_markdown, use \\n for newlines in the JSON string):

## [1-2 casual sentences — the week's overall throughline or arc]

### [Project Name]
[2-4 sentences: what evolved over the week, how it progressed day by day,
what problem it solves, any interesting angle. First person. Specific. Under 100 words per project.]

[Repeat ### section for each featured project]

## Also shipped
- [one-liner for each lower-signal item: dependency updates, minor fixes, config tweaks]

## By the numbers
- [X] commits across [Y] repos
- +[N] lines added, -[M] removed
[add any other notable stat]

[Optional: one closing sentence — what's next or a brief reflection]

RULES:
- body_markdown is a single JSON string value with \\n for newlines
- Use ## and ### only (not # or ####)
- Do NOT use: "leveraged", "implemented", "utilized", "robust", "seamless"
- Do NOT mention AI generating this
- Weave a narrative arc — show progression across the week, not isolated daily dumps
- Respond with ONLY the JSON object

DIGEST DATA:
{digest_data}"""

_BUILTIN_DAILY_PROMPT = """\
You are writing a brief "what I pushed today" developer log entry for a personal website.

Audience: same as a weekly post but this is shorter, more raw, more like a dev journal.
Tone: very casual, first person, quick. Like texting a dev friend about your day.
Voice: {author_voice}

Produce a JSON object:
{
  "title": "Today: [brief description]  — e.g. 'Today: Wired up the auth middleware'",
  "slug": "url-safe-version-max-60-chars",
  "excerpt": "1 sentence summary",
  "tags": ["lowercase-tag"],
  "body_markdown": "the full entry in markdown"
}

BODY STRUCTURE (150-250 words max, use \\n for newlines):

[1-2 sentences: what today was about overall]

[For each active repo — no subheadings needed for 1-2 repos, use ### for 3+]
[2-3 sentences: what you actually did, any blockers, any wins]

## Numbers
- [X] commits, +[N]/-[M] lines

[Optional: one sentence on what's next tomorrow]

RULES:
- Keep it short — this is a log entry not a blog post
- First person throughout
- Do NOT mention AI generating this
- Respond with ONLY the JSON object

DIGEST DATA:
{digest_data}"""


def _slugify(title: str) -> str:
    slug = title.lower()
    slug = re.sub(r"[^\w\s-]", "", slug)
    slug = re.sub(r"[\s_]+", "-", slug)
    slug = re.sub(r"-+", "-", slug).strip("-")
    return slug[:80]


class NarrativeWriter:
    def __init__(self, config: dict):
        self.client = anthropic.Anthropic(api_key=config["anthropic_api_key"])
        self.model = config.get("ai_model", "claude-sonnet-4-6")
        self.author_voice = config.get("digest", {}).get(
            "author_voice", "casual dev writing for other devs and potential clients"
        )
        self.token_usage = TokenUsage()

    def write(
        self,
        analyses: list[RepoAnalysis],
        since: datetime,
        until: datetime,
        cadence: str = "weekly",
        daily_refs: list[str] = None,
        out_dir: Path = None,
        date_prefix: str = None,
    ) -> DigestPost:
        """
        Generate the blog post from all repo analyses.

        cadence: "daily" | "weekly" | "rollup"
        daily_refs: doc IDs of daily drafts (for rollup only)
        out_dir + date_prefix: if provided, saves raw response on parse failure
        """
        log.info(f"Generating {cadence} narrative...")

        # Load prompt fresh each call so edits take effect immediately
        if cadence == "daily":
            template = _load_prompt("DAILY_NARRATIVE_PROMPT", _BUILTIN_DAILY_PROMPT)
        elif cadence == "rollup":
            template = _load_prompt("ROLLUP_NARRATIVE_PROMPT", _BUILTIN_ROLLUP_PROMPT)
        else:
            template = _load_prompt("WEEKLY_NARRATIVE_PROMPT", _BUILTIN_WEEKLY_PROMPT)

        digest_data = self._format_digest_data(analyses, since, until, cadence)
        prompt = (
            template
            .replace("{author_voice}", self.author_voice)
            .replace("{digest_data}", digest_data)
        )

        max_tokens = 1500 if cadence == "daily" else 4096

        raw = ""
        try:
            response = self.client.messages.create(
                model=self.model,
                max_tokens=max_tokens,
                messages=[{"role": "user", "content": prompt}],
            )
            self.token_usage.add(
                response.usage.input_tokens,
                response.usage.output_tokens,
            )
            log.info(
                f"  Narrative tokens: {response.usage.input_tokens}in/"
                f"{response.usage.output_tokens}out"
            )

            raw = response.content[0].text.strip()
            raw = strip_fences(raw)
            data = json.loads(raw)

        except json.JSONDecodeError as e:
            log.error(f"  Narrative JSON parse failed: {e}")
            # Salvage: save raw response so user can manually recover
            if out_dir and date_prefix:
                salvage_path = out_dir / f"{date_prefix}_narrative_raw.txt"
                salvage_path.write_text(raw or "(no response)")
                log.error(f"  Raw response saved to: {salvage_path}")
                log.error("  You can manually extract the post from that file.")
            raise RuntimeError(
                f"Narrative generation failed: JSON parse error. "
                f"Check {date_prefix}_narrative_raw.txt if available."
            ) from e
        except Exception as e:
            log.error(f"  Narrative API call failed: {e}")
            raise

        # Compute real stats from analyses — never trust AI for numbers
        stats = {
            "totalCommits": sum(a.commit_count for a in analyses),
            "reposActive": len(analyses),
            "linesAdded": sum(a.lines_added for a in analyses),
            "linesRemoved": sum(a.lines_removed for a in analyses),
        }

        projects = [
            {
                "repoName": a.repo_name,
                "projectType": a.project_type,
                "summary": a.work_summary,
                "skillsDemonstrated": a.skills_demonstrated,
                "url": a.url,
                "isPrivate": a.is_private,
            }
            for a in analyses
        ]

        title = data.get("title", f"Shipped: {week_label(since)}")
        slug = data.get("slug") or _slugify(title)

        # week_of is always the Monday of the week — never the arbitrary since date
        monday = monday_of_week(since)

        if cadence == "daily":
            period_label = day_label(since)
            date_field = iso_date(since)
        else:
            period_label = week_label(monday)
            date_field = iso_date(monday)

        return DigestPost(
            title=title,
            slug=slug,
            cadence=cadence,
            period_label=period_label,
            week_of=iso_date(monday),
            date=date_field,
            excerpt=data.get("excerpt", ""),
            body_markdown=data.get("body_markdown", ""),
            tags=data.get("tags", []),
            stats=stats,
            projects=projects,
            daily_refs=daily_refs or [],
        )

    def _format_digest_data(
        self,
        analyses: list[RepoAnalysis],
        since: datetime,
        until: datetime,
        cadence: str,
    ) -> str:
        interesting = [a for a in analyses if a.interesting]
        background = [a for a in analyses if not a.interesting]

        header_label = day_label(since) if cadence == "daily" else week_label(since)

        lines = [
            f"Period: {header_label} ({iso_date(since)} to {iso_date(until)})",
            f"Total commits: {sum(a.commit_count for a in analyses)}",
            f"Active repos: {len(analyses)}",
            f"Lines added: {sum(a.lines_added for a in analyses)}",
            f"Lines removed: {sum(a.lines_removed for a in analyses)}",
            "",
            "=== FEATURED WORK ===",
        ]

        for a in interesting:
            privacy_note = " [PRIVATE — describe type of work only]" if a.is_private else ""
            lines += [
                f"\nProject: {a.project_name} ({a.repo_name}){privacy_note}",
                f"Type: {a.project_type} | Language: {a.primary_language}",
                f"Commits: {a.commit_count} | +{a.lines_added}/-{a.lines_removed} lines",
                f"Summary: {a.work_summary}",
                f"Why interesting: {a.interesting_reason}",
                f"Skills: {', '.join(a.skills_demonstrated)}",
                f"Highlights: {'; '.join(a.technical_highlights)}",
            ]

        if background:
            lines += ["", "=== LOWER-SIGNAL WORK (brief mention only) ==="]
            for a in background:
                lines.append(
                    f"  {a.project_name}: {a.commit_count} commits — {a.work_summary}"
                )

        return "\n".join(lines)
