"""
github_fetcher.py — Fetch commit activity from GitHub for all repos in a date window.

Handles rate limiting, merge commit filtering, diff extraction, and
private/org repo visibility controls.
"""

import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional

from scripts.shared_utils import get_logger, iso_date

log = get_logger("fetcher")

try:
    from github import Github, GithubException
except ImportError:
    raise ImportError("PyGithub required. Install with: pip install PyGithub")

# Commit message prefixes that indicate merge commits — always skipped
MERGE_PREFIXES = ("Merge pull request", "Merge branch", "Merge remote-tracking")

# File patterns that are never useful to diff — skip their patch content
SKIP_DIFF_PATTERNS = (
    "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "Pipfile.lock",
    "poetry.lock", "Cargo.lock", "go.sum", "composer.lock",
    ".min.js", ".min.css", ".map", ".lock",
)


@dataclass
class CommitData:
    sha: str
    message: str
    timestamp: datetime
    files_changed: list[str]
    lines_added: int
    lines_removed: int
    diff_snippets: list[str]  # patch text from most-changed files, trimmed


@dataclass
class RepoActivity:
    repo_name: str
    repo_full_name: str
    description: str
    primary_language: str
    url: str
    is_fork: bool
    is_private: bool
    commits: list[CommitData] = field(default_factory=list)

    @property
    def commit_count(self) -> int:
        return len(self.commits)

    @property
    def lines_added(self) -> int:
        return sum(c.lines_added for c in self.commits)

    @property
    def lines_removed(self) -> int:
        return sum(c.lines_removed for c in self.commits)

    @property
    def all_files_changed(self) -> list[str]:
        seen: set[str] = set()
        result = []
        for c in self.commits:
            for f in c.files_changed:
                if f not in seen:
                    seen.add(f)
                    result.append(f)
        return result

    @property
    def most_changed_commit(self) -> Optional["CommitData"]:
        """Return the commit with the most lines changed — highest signal for diffs."""
        if not self.commits:
            return None
        return max(self.commits, key=lambda c: c.lines_added + c.lines_removed)


class GitHubFetcher:
    def __init__(self, config: dict):
        self.username = config["github_username"]
        self.token = config["github_token"]
        self.excluded_repos = set(config.get("excluded_repos", []))
        self.skip_forks = config.get("skip_forks", False)
        self.max_diff_files = config.get("max_diff_files", 20)
        self.include_orgs = config.get("include_orgs", [])
        self.private_mode = config.get("private_repos", "include")
        self._gh = Github(self.token, per_page=100)

    def fetch(self, since: datetime, until: datetime) -> list[RepoActivity]:
        """
        Fetch all repo activity for self.username within [since, until].
        Returns list of RepoActivity sorted by lines changed descending.
        Repos with no qualifying commits are excluded.
        """
        log.info(f"Fetching GitHub activity for @{self.username}")
        log.info(f"Date window: {iso_date(since)} → {iso_date(until)}")
        if self.private_mode != "include":
            log.info(f"Private repo mode: {self.private_mode}")

        repos = self._collect_repos()
        log.info(f"Found {len(repos)} repos to scan")

        activity = []
        for repo in repos:
            if repo.name in self.excluded_repos:
                log.info(f"  Skipping (excluded): {repo.name}")
                continue
            if self.skip_forks and repo.fork:
                log.info(f"  Skipping (fork): {repo.name}")
                continue
            if self.private_mode == "skip" and repo.private:
                log.info(f"  Skipping (private): {repo.name}")
                continue

            repo_activity = self._fetch_repo(repo, since, until)
            if repo_activity and repo_activity.commits:
                activity.append(repo_activity)
                log.info(
                    f"  ✓ {repo.name}: {repo_activity.commit_count} commits "
                    f"+{repo_activity.lines_added}/-{repo_activity.lines_removed}"
                    + (" [private]" if repo.private else "")
                )
            else:
                log.info(f"  — {repo.name}: no commits in window")

            self._check_rate_limit()

        # Sort by total lines changed desc — most active repos first
        activity.sort(key=lambda r: r.lines_added + r.lines_removed, reverse=True)
        log.info(f"Active repos: {len(activity)}")
        return activity

    def _collect_repos(self) -> list:
        """Collect repos from user account plus any configured orgs."""
        user = self._gh.get_user(self.username)
        repos = list(user.get_repos(type="owner", sort="updated"))

        for org_name in self.include_orgs:
            try:
                org = self._gh.get_organization(org_name)
                org_repos = list(org.get_repos())
                repos.extend(org_repos)
                log.info(f"  Added {len(org_repos)} repos from org: {org_name}")
            except GithubException as e:
                log.warning(f"  Could not access org '{org_name}': {e}")

        return repos

    def _fetch_repo(self, repo, since: datetime, until: datetime) -> Optional[RepoActivity]:
        """Fetch commits for a single repo. Returns None on error or no commits."""
        try:
            commits_paged = repo.get_commits(
                author=self.username,
                since=since,
                until=until,
            )
            commits = []
            for gh_commit in commits_paged:
                msg = gh_commit.commit.message.strip()
                if any(msg.startswith(p) for p in MERGE_PREFIXES):
                    continue
                commit_data = self._extract_commit(gh_commit)
                if commit_data:
                    commits.append(commit_data)

            if not commits:
                return None

            return RepoActivity(
                repo_name=repo.name,
                repo_full_name=repo.full_name,
                description=repo.description or "",
                primary_language=repo.language or "Unknown",
                url=repo.html_url,
                is_fork=repo.fork,
                is_private=repo.private,
                commits=commits,
            )
        except GithubException as e:
            log.warning(f"  Error fetching {repo.name}: {e}")
            return None

    def _extract_commit(self, gh_commit) -> Optional[CommitData]:
        """Extract structured data from a GitHub commit object."""
        try:
            files = gh_commit.files
            file_paths = [f.filename for f in files]
            lines_added = sum(f.additions for f in files)
            lines_removed = sum(f.deletions for f in files)

            diff_snippets = []
            if len(files) <= self.max_diff_files:
                # Sort files by lines changed desc — most signal first
                sorted_files = sorted(
                    files,
                    key=lambda f: f.additions + f.deletions,
                    reverse=True
                )
                for f in sorted_files[:5]:
                    # Skip lock files and minified assets — no useful signal
                    if any(f.filename.endswith(p) or f.filename == p
                           for p in SKIP_DIFF_PATTERNS):
                        continue
                    patch = getattr(f, "patch", None)
                    if patch:
                        diff_snippets.append(
                            f"--- {f.filename} ---\n{patch[:500]}"
                        )

            return CommitData(
                sha=gh_commit.sha[:8],
                message=gh_commit.commit.message.strip(),
                timestamp=gh_commit.commit.author.date,
                files_changed=file_paths,
                lines_added=lines_added,
                lines_removed=lines_removed,
                diff_snippets=diff_snippets,
            )
        except Exception as e:
            log.warning(f"    Could not extract commit {gh_commit.sha[:8]}: {e}")
            return None

    def _check_rate_limit(self) -> None:
        """Pause if GitHub rate limit is nearly exhausted."""
        try:
            rate = self._gh.get_rate_limit().core
            remaining = rate.remaining
            if remaining < 50:
                # Use timezone-aware now() to match rate.reset (which is UTC-aware)
                reset_in = max(
                    int((rate.reset - datetime.now(timezone.utc)).total_seconds()) + 5,
                    5
                )
                log.warning(
                    f"Rate limit low ({remaining} remaining). "
                    f"Pausing {reset_in}s until reset..."
                )
                time.sleep(reset_in)
        except Exception:
            pass  # non-fatal — best effort
