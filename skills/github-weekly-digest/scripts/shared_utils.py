"""
shared_utils.py — Config loading, date helpers, logging, output management.

All datetime objects returned are UTC-aware. Never use datetime.utcnow() anywhere
in this codebase — always use datetime.now(timezone.utc).
"""

import json
import logging
import os
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path


# ── Config ────────────────────────────────────────────────────────────────────

def load_config(config_path: str) -> dict:
    """Load config.json, then overlay secret fields from environment variables.

    Non-sensitive config (github_username, ai_model, etc.) comes from config.json.
    Sensitive credentials (tokens, API keys) are injected via env vars at runtime
    using run-with-secrets.sh. Env vars always win over config.json values.
    """
    path = Path(config_path)
    if not path.exists():
        raise FileNotFoundError(
            f"config.json not found at: {config_path}\n"
            f"Copy assets/config_template.json to config.json and fill in your values."
        )
    with open(path) as f:
        config = json.load(f)

    _ENV_OVERLAY = {
        "github_token":      "GITHUB_TOKEN",
        "anthropic_api_key":  "ANTHROPIC_API_KEY",
        "sanity_token":       "SANITY_TOKEN",
        "sanity_project_id":  "SANITY_PROJECT_ID",
        "sanity_dataset":     "SANITY_DATASET",
    }
    for config_key, env_var in _ENV_OVERLAY.items():
        val = os.environ.get(env_var)
        if val:
            config[config_key] = val

    required = [
        "github_username", "github_token",
        "anthropic_api_key",
        "sanity_project_id", "sanity_dataset", "sanity_token",
    ]
    missing = [k for k in required if not config.get(k)]
    if missing:
        raise ValueError(
            f"Missing required config: {missing}\n"
            f"Set via env vars (run-with-secrets.sh) or config.json.\n"
            f"See assets/config_template.json and ~/dotfiles/.env.secrets.example."
        )
    return config


# ── Date window ───────────────────────────────────────────────────────────────

def get_date_window(
    config: dict,
    since_str: str = None,
    until_str: str = None,
    cadence: str = "weekly",
) -> tuple[datetime, datetime]:
    """
    Return (since, until) as UTC-aware datetimes.

    daily  → today 00:00 UTC → now
    weekly → default_days ago → now  (or explicit since/until)
    rollup → last Mon 00:00 UTC → last Sun 23:59 UTC

    Explicit --since / --until always override cadence defaults.
    All returned datetimes are guaranteed timezone-aware (UTC).
    """
    fmt = "%Y-%m-%d"
    now = datetime.now(timezone.utc)

    if since_str and until_str:
        since = datetime.strptime(since_str, fmt).replace(
            hour=0, minute=0, second=0, microsecond=0, tzinfo=timezone.utc
        )
        until = datetime.strptime(until_str, fmt).replace(
            hour=23, minute=59, second=59, microsecond=0, tzinfo=timezone.utc
        )
        return since, until

    if cadence == "daily":
        since = now.replace(hour=0, minute=0, second=0, microsecond=0)
        until = now

    elif cadence == "rollup":
        today = now.replace(hour=0, minute=0, second=0, microsecond=0)
        # weekday(): Mon=0 … Sun=6
        # last Sunday = today minus (weekday+1) days; last Monday = Sunday-6
        last_sunday = today - timedelta(days=today.weekday() + 1)
        last_monday = last_sunday - timedelta(days=6)
        since = last_monday
        until = last_sunday.replace(hour=23, minute=59, second=59, microsecond=0)

    else:  # weekly
        if until_str:
            until = datetime.strptime(until_str, fmt).replace(
                hour=23, minute=59, second=59, microsecond=0, tzinfo=timezone.utc
            )
        else:
            until = now
        if since_str:
            since = datetime.strptime(since_str, fmt).replace(
                hour=0, minute=0, second=0, microsecond=0, tzinfo=timezone.utc
            )
        else:
            default_days = config.get("digest", {}).get("default_days", 7)
            since = (until - timedelta(days=default_days)).replace(
                hour=0, minute=0, second=0, microsecond=0, tzinfo=timezone.utc
            )

    # Defensive: guarantee UTC-aware on all paths
    if since.tzinfo is None:
        since = since.replace(tzinfo=timezone.utc)
    if until.tzinfo is None:
        until = until.replace(tzinfo=timezone.utc)

    return since, until


def week_label(since: datetime) -> str:
    """
    Return e.g. 'Week of January 6, 2025'.
    Uses since.day directly — avoids %-d which is Linux-only.
    """
    return f"Week of {since.strftime('%B')} {since.day}, {since.year}"


def day_label(dt: datetime) -> str:
    """Return e.g. 'Monday, January 6, 2025'."""
    return f"{dt.strftime('%A, %B')} {dt.day}, {dt.year}"


def iso_date(dt: datetime) -> str:
    """Return YYYY-MM-DD string."""
    return dt.strftime("%Y-%m-%d")


def monday_of_week(dt: datetime) -> datetime:
    """Return the Monday of the ISO week containing dt, at 00:00 UTC."""
    monday = dt - timedelta(days=dt.weekday())
    return monday.replace(hour=0, minute=0, second=0, microsecond=0, tzinfo=timezone.utc)


# ── Logging ───────────────────────────────────────────────────────────────────

def get_logger(name: str = "digest") -> logging.Logger:
    """
    Return a configured logger writing to stdout.
    Suppresses third-party loggers that emit Authorization headers at DEBUG.
    """
    for noisy in ("github", "urllib3", "requests", "httpx", "httpcore"):
        logging.getLogger(noisy).setLevel(logging.WARNING)

    logger = logging.getLogger(name)
    if not logger.handlers:
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(logging.Formatter(
            "%(asctime)s  %(levelname)-8s  %(message)s",
            datefmt="%H:%M:%S"
        ))
        logger.addHandler(handler)
        logger.setLevel(logging.INFO)
    return logger


# ── Output helpers ────────────────────────────────────────────────────────────

def ensure_output_dir(config: dict) -> Path:
    """Create and return the output directory."""
    out = Path(config.get("output", {}).get("json_output_dir", "./output/"))
    out.mkdir(parents=True, exist_ok=True)
    return out


def save_json(path: Path, data) -> None:
    """Save dict or list as formatted JSON."""
    with open(path, "w") as f:
        json.dump(data, f, indent=2, default=str)


def strip_fences(raw: str) -> str:
    """Remove markdown code fences if the model wraps its JSON response."""
    raw = raw.strip()
    if raw.startswith("```"):
        parts = raw.split("```")
        if len(parts) >= 3:
            content = parts[1]
            if content.startswith("json"):
                content = content[4:]
            return content.strip()
    return raw


def cleanup_old_outputs(out_dir: Path, retain_days: int) -> None:
    """Delete output files (json/md/txt) older than retain_days. Non-fatal."""
    if retain_days <= 0:
        return
    log = logging.getLogger("digest")
    cutoff = datetime.now(timezone.utc) - timedelta(days=retain_days)
    deleted = 0
    for pattern in ("*.json", "*.md", "*.txt"):
        for f in out_dir.glob(pattern):
            mtime = datetime.fromtimestamp(f.stat().st_mtime, tz=timezone.utc)
            if mtime < cutoff:
                try:
                    f.unlink()
                    deleted += 1
                except OSError:
                    pass
    if deleted:
        log.info(f"  Cleaned up {deleted} output file(s) older than {retain_days} days")


# ── Analysis persistence ──────────────────────────────────────────────────────

def save_analyses(path: Path, analyses: list) -> None:
    """Serialize a list of RepoAnalysis dataclasses to JSON."""
    from dataclasses import asdict
    save_json(path, [asdict(a) for a in analyses])


def load_analyses(path: Path) -> list:
    """
    Deserialize RepoAnalysis list from a saved JSON file.
    Used by --reuse-analysis and rollup cadence.
    """
    from scripts.commit_analyzer import RepoAnalysis
    with open(path) as f:
        raw = json.load(f)
    return [
        RepoAnalysis(
            repo_name=r["repo_name"],
            repo_full_name=r["repo_full_name"],
            url=r["url"],
            primary_language=r["primary_language"],
            project_name=r["project_name"],
            project_type=r["project_type"],
            work_summary=r["work_summary"],
            technical_highlights=r["technical_highlights"],
            skills_demonstrated=r["skills_demonstrated"],
            commit_count=r["commit_count"],
            lines_added=r["lines_added"],
            lines_removed=r["lines_removed"],
            interesting=r["interesting"],
            interesting_reason=r["interesting_reason"],
            is_private=r.get("is_private", False),
        )
        for r in raw
    ]


def merge_daily_analyses(daily_analyses_list: list) -> list:
    """
    Merge multiple days' RepoAnalysis lists into one for weekly rollup.
    Repos on multiple days: stats summed, highlights/skills unioned,
    interesting=True if any day was interesting.
    """
    from scripts.commit_analyzer import RepoAnalysis
    by_repo: dict[str, RepoAnalysis] = {}

    for day_analyses in daily_analyses_list:
        for a in day_analyses:
            key = a.repo_name
            if key not in by_repo:
                by_repo[key] = RepoAnalysis(
                    repo_name=a.repo_name,
                    repo_full_name=a.repo_full_name,
                    url=a.url,
                    primary_language=a.primary_language,
                    project_name=a.project_name,
                    project_type=a.project_type,
                    work_summary=a.work_summary,
                    technical_highlights=list(a.technical_highlights),
                    skills_demonstrated=list(a.skills_demonstrated),
                    commit_count=a.commit_count,
                    lines_added=a.lines_added,
                    lines_removed=a.lines_removed,
                    interesting=a.interesting,
                    interesting_reason=a.interesting_reason,
                    is_private=a.is_private,
                )
            else:
                ex = by_repo[key]
                ex.commit_count += a.commit_count
                ex.lines_added += a.lines_added
                ex.lines_removed += a.lines_removed
                seen_h = set(ex.technical_highlights)
                for h in a.technical_highlights:
                    if h not in seen_h:
                        ex.technical_highlights.append(h)
                        seen_h.add(h)
                seen_s = set(ex.skills_demonstrated)
                for s in a.skills_demonstrated:
                    if s not in seen_s:
                        ex.skills_demonstrated.append(s)
                        seen_s.add(s)
                if a.interesting and not ex.interesting:
                    ex.interesting = True
                    ex.interesting_reason = a.interesting_reason

    return list(by_repo.values())


# ── Token cost tracking ───────────────────────────────────────────────────────

MODEL_COSTS = {
    "claude-sonnet-4-6":         {"input": 3.00,  "output": 15.00},
    "claude-opus-4-6":           {"input": 15.00, "output": 75.00},
    "claude-haiku-4-5-20251001": {"input": 0.80,  "output":  4.00},
}


def estimate_cost(model: str, input_tokens: int, output_tokens: int) -> float:
    prices = MODEL_COSTS.get(model, MODEL_COSTS["claude-sonnet-4-6"])
    return (input_tokens * prices["input"] + output_tokens * prices["output"]) / 1_000_000


@dataclass
class TokenUsage:
    input_tokens: int = 0
    output_tokens: int = 0
    calls: int = 0

    def add(self, input_t: int, output_t: int) -> None:
        self.input_tokens += input_t
        self.output_tokens += output_t
        self.calls += 1

    def cost(self, model: str) -> float:
        return estimate_cost(model, self.input_tokens, self.output_tokens)

    def summary(self, model: str) -> str:
        return (
            f"{self.calls} API call(s) | "
            f"{self.input_tokens:,} in / {self.output_tokens:,} out | "
            f"~${self.cost(model):.4f}"
        )
