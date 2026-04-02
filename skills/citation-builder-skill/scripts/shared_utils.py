"""
shared_utils.py — Shared utilities used across multiple scripts.

Currently provides:
    discover_credentials() — auto-find service account JSON
    load_env() / ensure_env() — load secrets from ~/dotfiles/secrets/.env
    load_config() — load config.json with env var overrides for sensitive values
    validate_config() — validate all required config keys are present
    resolve_path() — expand ~ and resolve to absolute path
    due_date() — return YYYY-MM-DD date offset from today
    CircuitBreaker — track consecutive failures with threshold

Import from here instead of duplicating in each module:
    from scripts.shared_utils import discover_credentials, ensure_env, load_config, validate_config
"""

import glob
import json
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path

NOTE_MAX_LEN = 500

_ENV_FILES = [
    Path.home() / "dotfiles" / "secrets" / ".env",
    Path.home() / "dotfiles" / "secrets" / ".env.citation",
]


def _load_env_file(path: Path) -> None:
    """Load key=value pairs from an env file into os.environ.
    Skips blank lines, comments, and vars already set in the environment.
    Strips matching quotes and inline comments from values (bash source compat)."""
    for line_num, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()

        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key   = key.strip()
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
    """Load secrets into os.environ from ~/dotfiles/secrets/.env (primary)
    or ~/.env.citation (legacy fallback). Vars already set in the environment
    (e.g. from shell profile) take priority and are never overwritten.
    Also reconfigures stdout/stderr to UTF-8 on Windows."""
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
            + "\nCopy secrets/.env.example to secrets/.env and fill in values."
        )


def resolve_path(p: str) -> str:
    """Expand ~ and resolve to absolute path."""
    return str(Path(p).expanduser().resolve())


def _is_service_account(filepath: str) -> bool:
    """Return True if the JSON file looks like a GCP service account key."""
    try:
        with open(filepath, encoding="utf-8") as f:
            data = json.load(f)
        return data.get("type") == "service_account"
    except (json.JSONDecodeError, OSError):
        return False


def discover_credentials(config: dict = None) -> str:
    """
    Return path to the service account JSON file.

    Resolution order:
    1. GCP_CREDENTIALS_FILE environment variable
    2. config["credentials_file"] if present and non-empty
    3. Auto-discovery: glob ~/dotfiles/secrets/*.json

    Raises FileNotFoundError if no file found.
    Raises RuntimeError if multiple files found and nothing specifies which.
    """
    env_creds = os.environ.get("GCP_CREDENTIALS_FILE", "").strip()

    if env_creds:
        resolved = resolve_path(env_creds)

        if not os.path.exists(resolved):
            raise FileNotFoundError(
                f"GCP_CREDENTIALS_FILE points to missing file: {resolved}"
            )
        return resolved

    if config:
        explicit = config.get("credentials_file", "")

        if explicit:
            resolved = resolve_path(explicit)

            if not os.path.exists(resolved):
                raise FileNotFoundError(
                    f"credentials_file specified in config not found: {resolved}"
                )
            return resolved

    pattern = os.path.expanduser("~/dotfiles/secrets/*.json")
    matches = [
        f for f in glob.glob(pattern)
        if _is_service_account(f)
    ]

    if not matches:
        raise FileNotFoundError(
            f"No service account JSON found in ~/dotfiles/secrets/\n"
            f"Searched: {pattern}\n"
            f"Set GCP_CREDENTIALS_FILE env var, add 'credentials_file' to config.json, "
            f"or place your service account JSON in ~/dotfiles/secrets/."
        )

    if len(matches) > 1:
        raise RuntimeError(
            f"Multiple service account JSONs in ~/dotfiles/secrets/: {matches}\n"
            f"Set GCP_CREDENTIALS_FILE env var or add 'credentials_file' to config.json."
        )

    return matches[0]


_env_loaded = False


def ensure_env() -> None:
    """Idempotent wrapper around load_env(). Safe to call multiple times."""
    global _env_loaded
    if not _env_loaded:
        load_env()
        _env_loaded = True


def load_config(config_path: str) -> dict:
    """
    Load config.json and override sensitive fields from environment variables.
    Env vars always win over config file values — this lets config.json stay
    committed with placeholder values while real secrets live in .env.
    Automatically calls load_env() if not already loaded.
    """
    ensure_env()

    resolved = resolve_path(config_path)
    if not os.path.exists(resolved):
        raise FileNotFoundError(
            f"Config file not found: {resolved}\n"
            f"Copy config.example.json to config.json and fill in values."
        )

    with open(resolved) as f:
        config = json.load(f)

    env_spreadsheet = os.environ.get("CITATION_SPREADSHEET_ID", "").strip()

    if env_spreadsheet:
        config.setdefault("sheets", {})["spreadsheet_id"] = env_spreadsheet

    env_creds = os.environ.get("GCP_CREDENTIALS_FILE", "").strip()

    if env_creds:
        config["credentials_file"] = env_creds

    email_cfg = config.setdefault("email", {})
    env_verification = os.environ.get("CITATION_VERIFICATION_EMAIL", "").strip()

    if env_verification:
        email_cfg["verification_account"] = env_verification

    env_business = os.environ.get("CITATION_BUSINESS_EMAIL", "").strip()

    if env_business:
        email_cfg["business_email"] = env_business

    return config


def validate_config(config: dict) -> None:
    """Validate config has all required keys. Raises ValueError with details on failure."""
    errors = []

    required_paths = {
        "sheets.spreadsheet_id": "Set CITATION_SPREADSHEET_ID in secrets/.env or add to config.json",
        "sheets.citations_tab": "Add sheets.citations_tab to config.json",
        "sheets.summary_tab": "Add sheets.summary_tab to config.json",
        "nap_path": "Add nap_path to config.json",
        "evidence_path": "Add evidence_path to config.json",
        "credentials_path": "Add credentials_path to config.json",
        "session.max_submissions_per_session": "Add session section to config.json (see config.example.json)",
        "session.domain_cooldown_seconds": "Add session section to config.json",
        "session.circuit_breaker_threshold": "Add session section to config.json",
    }

    for key_path, hint in required_paths.items():
        keys = key_path.split(".")
        obj = config
        for k in keys:
            if not isinstance(obj, dict) or k not in obj:
                errors.append(f"Missing config key: {key_path} — {hint}")
                break
            obj = obj[k]
        else:
            if obj in (None, "", "YOUR_SPREADSHEET_ID_HERE"):
                errors.append(f"Config key has placeholder/empty value: {key_path} — {hint}")

    email_cfg = config.get("email", {})
    has_verification = bool(email_cfg.get("verification_account"))
    has_env_verification = bool(os.environ.get("CITATION_VERIFICATION_EMAIL", "").strip())
    if not has_verification and not has_env_verification:
        errors.append(
            "No verification email configured. "
            "Set CITATION_VERIFICATION_EMAIL in secrets/.env or add email.verification_account to config.json."
        )

    if errors:
        raise ValueError(
            "Config validation failed:\n" + "\n".join(f"  ✗ {e}" for e in errors)
        )


def due_date(days: int) -> str:
    """Return a YYYY-MM-DD date string offset from today by the given number of days."""
    return (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")


class CircuitBreaker:
    """Track consecutive failures and trip when threshold is reached."""

    def __init__(self, threshold: int = 5):
        self.consecutive_failures = 0
        self.threshold              = threshold

    def record_failure(self) -> bool:
        """Increment failure count. Returns True if breaker has tripped."""
        self.consecutive_failures += 1
        return self.consecutive_failures >= self.threshold

    def reset(self):
        self.consecutive_failures = 0

    @property
    def tripped(self) -> bool:
        return self.consecutive_failures >= self.threshold
