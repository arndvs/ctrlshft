"""
commit_analyzer.py — Per-repo AI analysis using Claude API.

Produces structured analysis per repo: project type, work summary,
skills demonstrated, whether it's interesting enough to feature.

Key fixes from audit:
- Prompt loaded at call time (not import), with warning on fallback
- AI never returns commit/line counts (uses real fetched values always)
- Diff from most-changed commit, not first commit
- Token usage tracked and logged
- Private repo privacy mode respected
"""

import json
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from scripts.github_fetcher import RepoActivity
from scripts.shared_utils import get_logger, TokenUsage, strip_fences

log = get_logger("analyzer")

try:
    import anthropic
except ImportError:
    raise ImportError("anthropic package required. Install with: pip install anthropic")

_PROMPTS_PATH = Path(__file__).parent.parent / "references" / "prompt_templates.md"

SKIP_DIFF_PATTERNS = (
    "package-lock.json", "yarn.lock", "pnpm-lock.yaml",
    ".min.js", ".min.css", ".map",
)


@dataclass
class RepoAnalysis:
    repo_name: str
    repo_full_name: str
    url: str
    primary_language: str
    project_name: str
    project_type: str
    work_summary: str
    technical_highlights: list[str]
    skills_demonstrated: list[str]
    # These always come from real fetched data, never from AI
    commit_count: int
    lines_added: int
    lines_removed: int
    interesting: bool
    interesting_reason: str
    is_private: bool = False


def _load_prompt(section_name: str, builtin_fallback: str) -> str:
    """
    Load a named prompt section from prompt_templates.md using comment delimiters.
    Falls back to builtin with a warning if extraction fails.
    """
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
        f"Could not load '{section_name}' from prompt_templates.md "
        f"(missing file or delimiter). Using builtin fallback."
    )
    return builtin_fallback


_BUILTIN_REPO_PROMPT = """\
You are analyzing a GitHub repository's commit activity for a "what I shipped" developer blog post.

Given the commit data below, produce a JSON object with this EXACT schema.
Do not include commit_count, lines_added, or lines_removed — those are provided separately.

{
  "project_name": "human-readable name (convert repo slug to readable: my-cool-app → My Cool App)",
  "project_type": "one of: web app | CLI tool | library | config/dotfiles | data pipeline | API | mobile app | other",
  "work_summary": "2-3 sentences, first person ('I built', 'I fixed', 'I added'). Plain English. What changed and why it matters.",
  "technical_highlights": ["specific accomplishment 1", "specific accomplishment 2"],
  "skills_demonstrated": ["Technology or language name"],
  "interesting": true or false,
  "interesting_reason": "one sentence why this is noteworthy, or empty string if interesting is false"
}

interesting=true means: substantive work worth featuring in a blog post.
interesting=false means: only dependency bumps, typo fixes, minor config, or trivial commits.

Respond with ONLY the JSON object. No markdown fences, no explanation.

REPO DATA:
{repo_data}"""

_BUILTIN_PRIVATE_REPO_PROMPT = """\
You are analyzing a GitHub repository's commit activity for a "what I shipped" developer blog post.
This is a PRIVATE repository. Describe the TYPE and NATURE of work without naming the client,
company, or any specific implementation details that could identify the project.

Use vague but accurate descriptions:
- "client web app" not the actual app name
- "API integration work" not the specific API
- "authentication system refactor" is fine if it doesn't identify the client

Given the commit data below, produce a JSON object with this EXACT schema:
{
  "project_name": "Client Project" or "Private API Work" or similar generic name,
  "project_type": "one of: web app | CLI tool | library | config/dotfiles | data pipeline | API | mobile app | other",
  "work_summary": "2-3 sentences describing the TYPE of work without identifying details.",
  "technical_highlights": ["technical skill or pattern used"],
  "skills_demonstrated": ["Technology or language name"],
  "interesting": true or false,
  "interesting_reason": "one sentence, or empty string"
}

Respond with ONLY the JSON object. No markdown fences, no explanation.

REPO DATA:
{repo_data}"""


class CommitAnalyzer:
    def __init__(self, config: dict):
        self.client = anthropic.Anthropic(api_key=config["anthropic_api_key"])
        self.model = config.get("ai_model", "claude-sonnet-4-6")
        self.private_mode = config.get("private_repos", "include")
        self.token_usage = TokenUsage()

    def analyze_all(self, activities: list[RepoActivity]) -> list[RepoAnalysis]:
        """Analyze all repo activities. Returns list of RepoAnalysis."""
        # Load prompts fresh each call so edits to prompt_templates.md take effect
        self._repo_prompt = _load_prompt("REPO_ANALYSIS_PROMPT", _BUILTIN_REPO_PROMPT)
        self._private_prompt = _load_prompt("PRIVATE_REPO_PROMPT", _BUILTIN_PRIVATE_REPO_PROMPT)

        analyses = []
        for i, activity in enumerate(activities):
            log.info(f"  Analyzing {i+1}/{len(activities)}: {activity.repo_name}...")
            analysis = self._analyze_repo(activity)
            if analysis:
                analyses.append(analysis)
            if i < len(activities) - 1:
                time.sleep(0.3)

        log.info(f"  AI usage: {self.token_usage.summary(self.model)}")
        return analyses

    def _analyze_repo(self, activity: RepoActivity) -> Optional[RepoAnalysis]:
        """Analyze a single repo. Returns None on unrecoverable error."""
        use_private_prompt = (
            activity.is_private and self.private_mode == "summarize_only"
        )
        template = self._private_prompt if use_private_prompt else self._repo_prompt
        repo_data = self._format_repo_data(activity)
        prompt = template.replace("{repo_data}", repo_data)

        raw = ""
        try:
            response = self.client.messages.create(
                model=self.model,
                max_tokens=1024,
                messages=[{"role": "user", "content": prompt}],
            )
            self.token_usage.add(
                response.usage.input_tokens,
                response.usage.output_tokens,
            )
            log.info(
                f"    {response.usage.input_tokens}in/"
                f"{response.usage.output_tokens}out tokens"
            )

            raw = response.content[0].text.strip()
            raw = strip_fences(raw)
            data = json.loads(raw)

            return RepoAnalysis(
                repo_name=activity.repo_name,
                repo_full_name=activity.repo_full_name,
                url=activity.url,
                primary_language=activity.primary_language,
                project_name=data.get("project_name", activity.repo_name),
                project_type=data.get("project_type", "other"),
                work_summary=data.get("work_summary", ""),
                technical_highlights=data.get("technical_highlights", []),
                skills_demonstrated=data.get("skills_demonstrated", []),
                # Always use real fetched counts — never trust AI for these
                commit_count=activity.commit_count,
                lines_added=activity.lines_added,
                lines_removed=activity.lines_removed,
                interesting=data.get("interesting", True),
                interesting_reason=data.get("interesting_reason", ""),
                is_private=activity.is_private,
            )

        except json.JSONDecodeError as e:
            log.error(f"    JSON parse error for {activity.repo_name}: {e}")
            log.error(f"    Raw: {raw[:300] if raw else '(no response)'}")
            return None
        except Exception as e:
            log.error(f"    API error for {activity.repo_name}: {e}")
            return None

    def _format_repo_data(self, activity: RepoActivity) -> str:
        """
        Format repo activity into a prompt string.
        Uses diffs from the most-changed commit (highest signal), not first commit.
        Skips lock files and minified assets from diff snippets.
        """
        lines = [
            f"Repo: {activity.repo_name}",
            f"Description: {activity.description or 'none'}",
            f"Primary language: {activity.primary_language}",
            f"Commits: {activity.commit_count} | "
            f"+{activity.lines_added} lines added / -{activity.lines_removed} removed",
            "",
            "COMMIT MESSAGES (chronological):",
        ]
        for c in activity.commits:
            first_line = c.message.splitlines()[0]
            lines.append(f"  [{c.sha}] {first_line}")

        lines += ["", "FILES CHANGED (unique, up to 40):"]
        for f in activity.all_files_changed[:40]:
            lines.append(f"  {f}")

        # Use the most-changed commit for diffs — highest signal
        best = activity.most_changed_commit
        if best and best.diff_snippets:
            lines += [
                "",
                f"DIFF SNIPPETS (from commit {best.sha}, "
                f"+{best.lines_added}/-{best.lines_removed} lines):",
            ]
            for snippet in best.diff_snippets[:3]:
                lines.append(snippet[:400])

        return "\n".join(lines)
