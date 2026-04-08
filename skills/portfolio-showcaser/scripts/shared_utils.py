"""
shared_utils.py — Shared utilities for portfolio-showcaser skill.

Provides:
    load_env() / ensure_env() — load env from ~/dotfiles/secrets/.env.agent and .env.secrets
    load_config() — load config.json with env var overrides
    validate_config() — validate all required config keys are present
    validate_repo_path() — check that repo path exists and contains project files
    resolve_path(p) — expand ~ and resolve to absolute path
    due_date(days) — return YYYY-MM-DD date offset from today
    CircuitBreaker — track consecutive failures with threshold

Usage:
    from scripts.shared_utils import ensure_env, load_config, validate_config, resolve_path
"""

import json
import os
import shutil
import sys
from datetime import datetime
from pathlib import Path


_ENV_FILES = [
    Path.home() / "dotfiles" / "secrets" / ".env.agent",
    Path.home() / "dotfiles" / "secrets" / ".env.secrets",
    Path.home() / "dotfiles" / "secrets" / ".env",
]

PROJECT_SIGNATURES = [
    "package.json", "requirements.txt", "pyproject.toml", "composer.json",
    "Gemfile", "pom.xml", "build.gradle", "Cargo.toml", "go.mod", "index.html",
    "Makefile", "setup.py", "CMakeLists.txt",
]

REQUIRED_CONFIG = {
    "repo_path": "Path to the project to analyze",
    "output_dir": "Directory for reports and evidence",
    "state_file": "Path to the JSON state file",
    "exploration.max_features": "Feature budget per run",
}


def _load_env_file(path: Path) -> None:
    """Load key=value pairs from an env file into os.environ."""
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip()

        if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
            value = value[1:-1]
        else:
            comment_idx = value.find("  #")
            if comment_idx == -1:
                comment_idx = value.find("\t#")
            if comment_idx >= 0:
                value = value[:comment_idx].rstrip()

        value = os.path.expandvars(os.path.expanduser(value))

        if key and not os.environ.get(key):
            os.environ[key] = value


def load_env() -> None:
    """Load env vars from ~/dotfiles/secrets/.env.agent and .env.secrets."""
    stdout_enc = getattr(sys.stdout, "encoding", None) or ""
    if stdout_enc.lower() not in ("utf-8", "utf8"):
        if hasattr(sys.stdout, "reconfigure"):
            sys.stdout.reconfigure(encoding="utf-8", errors="replace")
            sys.stderr.reconfigure(encoding="utf-8", errors="replace")

    loaded = False
    for env_file in _ENV_FILES:
        if env_file.exists():
            _load_env_file(env_file)
            loaded = True

    if not loaded:
        raise FileNotFoundError(
            f"No secrets env file found. Searched:\n"
            + "\n".join(f"  {p}" for p in _ENV_FILES)
            + "\nCopy .env.agent.example to secrets/.env.agent"
        )


def resolve_path(p: str) -> str:
    """Expand ~ and resolve to absolute path."""
    return str(Path(p).expanduser().resolve())


_env_loaded = False


def ensure_env() -> None:
    """Idempotent wrapper around load_env(). Safe to call multiple times."""
    global _env_loaded
    if not _env_loaded:
        load_env()
        _env_loaded = True


def load_config(config_path: str) -> dict:
    """Load config.json and override repo_path from PORTFOLIO_REPO_PATH env var if set."""
    ensure_env()

    resolved = resolve_path(config_path)
    if not os.path.exists(resolved):
        raise FileNotFoundError(
            f"Config file not found: {resolved}\n"
            f"Copy config.example.json to config.json and fill in values."
        )

    with open(resolved) as f:
        config = json.load(f)

    env_repo = os.environ.get("PORTFOLIO_REPO_PATH", "").strip()
    if env_repo:
        config["repo_path"] = env_repo

    return config


def validate_config(config: dict) -> None:
    """Validate config has all required keys. Raises ValueError with details on failure."""
    errors = []

    for key_path, hint in REQUIRED_CONFIG.items():
        keys = key_path.split(".")
        obj = config
        for k in keys:
            if not isinstance(obj, dict) or k not in obj:
                errors.append(f"Missing config key: {key_path} — {hint}")
                break
            obj = obj[k]
        else:
            if obj in (None, "", "/path/to/your/project"):
                errors.append(f"Config key has placeholder/empty value: {key_path} — {hint}")

    if errors:
        raise ValueError(
            "Config validation failed:\n" + "\n".join(f"  ✗ {e}" for e in errors)
        )


def validate_repo_path(repo_path: str) -> None:
    """Check that repo path exists and contains recognizable project files."""
    resolved = resolve_path(repo_path)
    if not os.path.isdir(resolved):
        raise FileNotFoundError(f"Repo path does not exist or is not a directory: {resolved}")

    found = [sig for sig in PROJECT_SIGNATURES if os.path.exists(os.path.join(resolved, sig))]
    if not found:
        raise ValueError(
            f"No recognizable project files found in {resolved}.\n"
            f"Expected at least one of: {', '.join(PROJECT_SIGNATURES)}"
        )


def detect_package_manager(repo_path: str) -> str:
    """Detect the package manager for a project by lockfile presence."""
    repo = Path(repo_path)

    lockfile_map = {
        "pnpm-lock.yaml": "pnpm",
        "bun.lockb": "bun",
        "bun.lock": "bun",
        "yarn.lock": "yarn",
        "package-lock.json": "npm",
    }

    for lockfile, pm in lockfile_map.items():
        if (repo / lockfile).exists():
            return pm

    if (repo / "package.json").exists():
        return "npm"

    if (repo / "requirements.txt").exists() or (repo / "pyproject.toml").exists():
        return "pip"

    return "unknown"


def check_command_available(cmd: str) -> bool:
    """Return True if a command is available on PATH."""
    return shutil.which(cmd) is not None


class CircuitBreaker:
    """Track consecutive failures and trip when threshold is reached."""

    def __init__(self, threshold: int = 5):
        self.consecutive_failures = 0
        self.threshold = threshold

    def record_failure(self) -> bool:
        """Increment failure count. Returns True if breaker has tripped."""
        self.consecutive_failures += 1
        return self.consecutive_failures >= self.threshold

    def record_success(self) -> None:
        self.consecutive_failures = 0

    def reset(self):
        self.consecutive_failures = 0

    @property
    def tripped(self) -> bool:
        return self.consecutive_failures >= self.threshold
