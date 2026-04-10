# Pattern Catalog — Reusable Skill Infrastructure

Complete code patterns extracted from the citation-builder-skill. Each pattern is production-tested and ready to copy into new skills with minimal customization.

**Critical rule:** When generating code from these patterns, do NOT include the `CUSTOMIZE:` markers in the output. Those are instructions for the agent during generation — replace them with actual skill-specific code. Generated Python files must have zero comment lines (per global instructions).

---

## Pattern 1: Environment + Config Layering

**Purpose:** Load secrets from env files, merge with config.json, validate everything.

**Customization points:**

- `_ENV_FILES` — which `.env` files to load
- `ENV_PREFIX` — skill-specific env var prefix (e.g., `PORTFOLIO_`, `SCRAPER_`)
- `validate_config()` — required keys dict

```python
import glob
import json
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path

NOTE_MAX_LEN = 500

_ENV_FILES = [
    Path.home() / "dotfiles" / "secrets" / ".env",
    # CUSTOMIZE: add skill-specific env file, e.g. Path.home() / "dotfiles" / "secrets" / ".env.{skill_name}"
]


def _load_env_file(path: Path) -> None:
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
            + "\nCopy .env.agent.example to secrets/.env.agent and .env.secrets.example to secrets/.env.secrets"
        )


_env_loaded = False

def ensure_env() -> None:
    global _env_loaded
    if not _env_loaded:
        load_env()
        _env_loaded = True


def resolve_path(p: str) -> str:
    return str(Path(p).expanduser().resolve())


def load_config(config_path: str) -> dict:
    ensure_env()
    resolved = resolve_path(config_path)
    if not os.path.exists(resolved):
        raise FileNotFoundError(f"Config file not found: {resolved}")
    with open(resolved) as f:
        config = json.load(f)
    # CUSTOMIZE: overlay env vars for sensitive config fields
    # CUSTOMIZE: e.g. env_val = os.environ.get("{PREFIX}_SPREADSHEET_ID", "").strip()
    # CUSTOMIZE: if env_val: config.setdefault("state_store", {})["spreadsheet_id"] = env_val
    return config


def validate_config(config: dict) -> None:
    # CUSTOMIZE: add required keys for your skill
    required_paths = {
        # CUSTOMIZE: "section.key": "Error message hint",
    }
    errors = []
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
    if errors:
        raise ValueError("Config validation failed:\n" + "\n".join(f"  ✗ {e}" for e in errors))


def due_date(days: int) -> str:
    return (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")
```

---

## Pattern 2: Circuit Breaker

**Purpose:** Halt batch processing when systemic failures occur (IP block, browser crash, auth revoked).

```python
class CircuitBreaker:
    def __init__(self, threshold: int = 5):
        self.consecutive_failures = 0
        self.threshold = threshold

    def record_failure(self) -> bool:
        self.consecutive_failures += 1
        return self.consecutive_failures >= self.threshold

    def reset(self):
        self.consecutive_failures = 0

    @property
    def tripped(self) -> bool:
        return self.consecutive_failures >= self.threshold
```

---

## Pattern 3: GCP Service Account Auto-Discovery

**Purpose:** Find the service account JSON without hardcoding paths. Used by Sheets and Gmail API clients.

```python
def _is_service_account(filepath: str) -> bool:
    try:
        with open(filepath, encoding="utf-8") as f:
            data = json.load(f)
        return data.get("type") == "service_account"
    except (json.JSONDecodeError, OSError):
        return False


def discover_credentials(config: dict = None) -> str:
    env_creds = os.environ.get("GCP_CREDENTIALS_FILE", "").strip()
    if env_creds:
        resolved = resolve_path(env_creds)
        if not os.path.exists(resolved):
            raise FileNotFoundError(f"GCP_CREDENTIALS_FILE points to missing file: {resolved}")
        return resolved

    if config:
        explicit = config.get("credentials_file", "")
        if explicit:
            resolved = resolve_path(explicit)
            if not os.path.exists(resolved):
                raise FileNotFoundError(f"credentials_file specified in config not found: {resolved}")
            return resolved

    pattern = os.path.expanduser("~/dotfiles/secrets/*.json")
    matches = [f for f in glob.glob(pattern) if _is_service_account(f)]

    if not matches:
        raise FileNotFoundError(f"No service account JSON found. Searched: {pattern}")
    if len(matches) > 1:
        raise RuntimeError(f"Multiple service account JSONs found: {matches}. Specify one via GCP_CREDENTIALS_FILE or config.")
    return matches[0]
```

---

## Pattern 4: Google Sheets State Store

**Purpose:** Persistent, human-readable state tracking with exponential backoff retry.

**Customization points:**

- `COL` — column name → index mapping
- `HEADERS` — header row
- `STATUS_CODES` — valid statuses
- `SKIP_ON_STARTUP` — statuses that mean "done"

```python
import time
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

from scripts.shared_utils import discover_credentials, NOTE_MAX_LEN

SCOPES = ["https://www.googleapis.com/auth/spreadsheets"]
_MAX_RETRIES = 5
_BACKOFF_BASE = 2

def _execute_with_retry(request):
    for attempt in range(_MAX_RETRIES):
        try:
            return request.execute()
        except HttpError as e:
            if e.resp.status == 429 and attempt < _MAX_RETRIES - 1:
                wait = _BACKOFF_BASE ** attempt
                print(f"  Sheets API rate limited. Waiting {wait}s...")
                time.sleep(wait)
            else:
                raise

def _col_index_to_letter(index: int) -> str:
    result = ""
    index += 1
    while index > 0:
        index, remainder = divmod(index - 1, 26)
        result = chr(65 + remainder) + result
    return result


class SheetsClient:
    def __init__(self, config: dict):
        self.spreadsheet_id = config["state_store"]["spreadsheet_id"]
        self.main_tab = config["state_store"]["tab_name"]
        self.summary_tab = config["state_store"]["summary_tab"]

        creds_file = discover_credentials(config)
        creds = service_account.Credentials.from_service_account_file(creds_file, scopes=SCOPES)
        service = build("sheets", "v4", credentials=creds)
        self.sheet = service.spreadsheets()

    def get_all_items(self) -> list[dict]:
        num_cols = len(HEADERS)
        max_col = _col_index_to_letter(num_cols - 1)
        result = _execute_with_retry(self.sheet.values().get(
            spreadsheetId=self.spreadsheet_id,
            range=f"{self.main_tab}!A2:{max_col}",
        ))
        rows = result.get("values", [])
        items = []
        for i, row in enumerate(rows):
            padded = row + [""] * (num_cols - len(row))
            entry = {key: padded[idx] for key, idx in COL.items()}
            entry["_row_index"] = i + 2
            if entry.get(list(COL.keys())[0]):
                items.append(entry)
        return items

    def get_pending_items(self) -> list[dict]:
        return [i for i in self.get_all_items() if i["status"] not in SKIP_ON_STARTUP]

    def update_item(self, row_index: int, updates: dict) -> None:
        data = []
        for col_name, value in updates.items():
            if col_name not in COL:
                continue
            col_letter = _col_index_to_letter(COL[col_name])
            data.append({
                "range": f"{self.main_tab}!{col_letter}{row_index}",
                "values": [[str(value) if value is not None else ""]],
            })
        if data:
            _execute_with_retry(self.sheet.values().batchUpdate(
                spreadsheetId=self.spreadsheet_id,
                body={"valueInputOption": "USER_ENTERED", "data": data},
            ))

    def set_status(self, row_index: int, status: str, notes: str = None) -> None:
        if status not in STATUS_CODES:
            raise ValueError(f"Invalid status '{status}'. Valid: {sorted(STATUS_CODES)}")
        updates = {"status": status}
        if notes is not None:
            updates["notes"] = notes[:NOTE_MAX_LEN]
        self.update_item(row_index, updates)

    def setup_headers(self) -> None:
        max_col = _col_index_to_letter(len(HEADERS) - 1)
        _execute_with_retry(self.sheet.values().update(
            spreadsheetId=self.spreadsheet_id,
            range=f"{self.main_tab}!A1:{max_col}1",
            valueInputOption="USER_ENTERED",
            body={"values": [HEADERS]},
        ))
```

---

## Pattern 5: JSON State Store (Sheets Alternative)

**Purpose:** Local file state store for offline/VPS operation. Atomic writes prevent corruption.

```python
import json
import tempfile
import os
from pathlib import Path
from datetime import datetime

NOTE_MAX_LEN = 500

# CUSTOMIZE: statuses that mean "done" — items with these statuses are skipped on startup
SKIP_STATUSES = {"completed", "verified", "skipped"}

class JsonStateStore:
    def __init__(self, state_path: str):
        self.state_path = Path(state_path)
        if not self.state_path.exists():
            self._save({"items": [], "summary": {}})

    def _load(self) -> dict:
        return json.loads(self.state_path.read_text(encoding="utf-8"))

    def _save(self, data: dict) -> None:
        fd, tmp = tempfile.mkstemp(dir=self.state_path.parent, suffix=".tmp")
        try:
            os.write(fd, json.dumps(data, indent=2).encode())
            os.close(fd)
            fd = -1
            Path(tmp).replace(self.state_path)
        except Exception:
            if fd >= 0:
                os.close(fd)
            Path(tmp).unlink(missing_ok=True)
            raise

    def get_all_items(self) -> list[dict]:
        return self._load()["items"]

    def get_pending_items(self) -> list[dict]:
        return [i for i in self.get_all_items() if i.get("status") not in SKIP_STATUSES]

    def update_item(self, item_id: str, updates: dict) -> None:
        data = self._load()
        for item in data["items"]:
            if item["id"] == item_id:
                item.update(updates)
                break
        self._save(data)

    def set_status(self, item_id: str, status: str, notes: str = None) -> None:
        updates = {"status": status}
        if notes is not None:
            updates["notes"] = notes[:NOTE_MAX_LEN]
        self.update_item(item_id, updates)

    def add_item(self, item: dict) -> None:
        data = self._load()
        data["items"].append(item)
        self._save(data)

    def write_summary(self) -> None:
        data = self._load()
        counts = {}
        for item in data["items"]:
            s = item.get("status", "not_started")
            counts[s] = counts.get(s, 0) + 1
        data["summary"] = {
            "total": len(data["items"]),
            "status_counts": counts,
            "last_updated": datetime.now().isoformat(),
        }
        self._save(data)
```

---

## Pattern 6: Preflight Validation

**Purpose:** Validate all dependencies before starting. One shot, shows all errors at once.

**Customization:** Replace the check list with skill-specific requirements.

```python
import argparse
import sys
from pathlib import Path

from scripts.shared_utils import ensure_env, load_config, validate_config, resolve_path


def run_preflight(config_path: str) -> bool:
    ensure_env()
    print("=" * 50)
    print("Pre-flight Validation")
    print("=" * 50)

    config = load_config(config_path)
    errors = []

    try:
        validate_config(config)
        print("  ✓ Config structure valid")
    except ValueError as e:
        errors.append(str(e))

    for dir_key in ("evidence_path", "report_path"):
        path = resolve_path(config.get("output", {}).get(dir_key, f"./{dir_key}/"))
        Path(path).mkdir(parents=True, exist_ok=True)
        print(f"  ✓ Directory ready: {path}")

    # CUSTOMIZE: add Google Sheets connectivity check (if using Sheets)
    # CUSTOMIZE: add external service access checks
    # CUSTOMIZE: add runtime dependency checks (node, python, etc.)

    if errors:
        print("\nERRORS (must fix):")
        for e in errors:
            print(f"  ✗ {e}")
        print("\nPre-flight FAILED.")
        return False
    print("\nPre-flight PASSED.")
    return True


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run pre-flight validation")
    parser.add_argument("--config", required=True, help="Path to config.json")
    args = parser.parse_args()
    sys.exit(0 if run_preflight(args.config) else 1)
```

---

## Pattern 7: Encrypted Credential Vault

**Purpose:** AES-256 encrypted storage for account credentials. Only include if skill creates/manages external accounts.

Key must come from `{PREFIX}_VAULT_KEY` env var — never from config files.

```python
import json
import os
import tempfile
from pathlib import Path
from datetime import datetime
from cryptography.fernet import Fernet, InvalidToken

def _get_fernet(env_var: str = "VAULT_KEY") -> Fernet:
    key = os.environ.get(env_var, "").strip()
    if not key:
        raise EnvironmentError(f"{env_var} environment variable is not set.")
    try:
        return Fernet(key.encode())
    except Exception as e:
        raise ValueError(f"{env_var} is not a valid Fernet key: {e}") from e

def init_vault(vault_path: str, env_var: str = "VAULT_KEY") -> None:
    path = Path(vault_path)
    if path.exists():
        print(f"Vault already exists at {vault_path}")
        return
    fernet = _get_fernet(env_var)
    encrypted = fernet.encrypt(json.dumps({}).encode())
    path.write_bytes(encrypted)
    print(f"Empty vault initialized at {vault_path}")

def _load_vault(vault_path: str, env_var: str = "VAULT_KEY") -> dict:
    path = Path(vault_path)
    if not path.exists():
        return {}
    fernet = _get_fernet(env_var)
    try:
        return json.loads(fernet.decrypt(path.read_bytes()))
    except InvalidToken:
        raise ValueError(f"Failed to decrypt vault. Check {env_var}.")

def _save_vault(vault_path: str, vault: dict, env_var: str = "VAULT_KEY") -> None:
    fernet = _get_fernet(env_var)
    encrypted = fernet.encrypt(json.dumps(vault, indent=2).encode())
    path = Path(vault_path)
    fd, tmp = tempfile.mkstemp(dir=path.parent, suffix=".tmp")
    try:
        os.write(fd, encrypted)
        os.close(fd)
        fd = -1
        Path(tmp).replace(path)
    except Exception:
        if fd >= 0:
            os.close(fd)
        Path(tmp).unlink(missing_ok=True)
        raise

def get_credentials(vault_path: str, key: str) -> dict | None:
    return _load_vault(vault_path).get(key)

def store_credentials(vault_path: str, key: str, **kwargs) -> None:
    vault = _load_vault(vault_path)
    now = datetime.now().strftime("%Y-%m-%d")
    existing = vault.get(key, {})
    vault[key] = {**kwargs, "created_date": existing.get("created_date", now), "last_updated": now}
    _save_vault(vault_path, vault)
```

---

## Pattern 8: Browser Adapter Interface

**Purpose:** Single interface for VS Code browser tools (local) and Playwright (VPS).

```python
from abc import ABC, abstractmethod

class BrowserAdapter(ABC):
    @abstractmethod
    def navigate(self, url: str) -> None: ...

    @abstractmethod
    def screenshot(self, path: str = None) -> bytes: ...

    @abstractmethod
    def click(self, selector: str) -> None: ...

    @abstractmethod
    def type_text(self, selector: str, text: str) -> None: ...

    @abstractmethod
    def read_text(self, selector: str = None) -> str: ...

    @abstractmethod
    def wait_for(self, selector: str, timeout: int = 30000) -> None: ...

    @abstractmethod
    def evaluate(self, js: str) -> Any: ...

    @abstractmethod
    def set_viewport(self, width: int, height: int) -> None: ...


class PlaywrightAdapter(BrowserAdapter):
    def __init__(self, page):
        self.page = page

    def navigate(self, url: str) -> None:
        self.page.goto(url, wait_until="networkidle")

    def screenshot(self, path: str = None) -> bytes:
        return self.page.screenshot(path=path)

    def click(self, selector: str) -> None:
        self.page.click(selector)

    def type_text(self, selector: str, text: str) -> None:
        self.page.fill(selector, text)

    def read_text(self, selector: str = None) -> str:
        if selector:
            return self.page.text_content(selector)
        return self.page.content()

    def wait_for(self, selector: str, timeout: int = 30000) -> None:
        self.page.wait_for_selector(selector, timeout=timeout)

    def evaluate(self, js: str):
        return self.page.evaluate(js)

    def set_viewport(self, width: int, height: int) -> None:
        self.page.set_viewport_size({"width": width, "height": height})
```

**VS Code mode note:** In VS Code mode, the agent does NOT use a Python adapter. The agent calls VS Code browser MCP tools directly (`open_browser_page`, `click_element`, etc.) and manually drives the orchestrator's phase methods. The `PlaywrightAdapter` class is only for VPS headless execution.

---

## Pattern 9: Orchestrator Error Boundary Structure

**Purpose:** Safely process batches with proper error isolation between phases.

```
Pre-execution phases (1-4):
  ├─ try/except → mark "failed" on exception
  ├─ each phase returns {skip: bool}
  └─ safe to retry from the beginning

Point of no return (phase 5):
  ├─ try/except → mark "failed" on exception
  ├─ if success → increment counter, reset circuit breaker
  └─ irreversible action (submission, write, mutation)

Post-execution phases (6-7):
  ├─ try/except → append note only, NEVER revert status
  ├─ QA, verification, cleanup
  └─ failures here don't block the overall pipeline
```

---

## Pattern 10: Rate Limiting and Cooldowns

Always include configurable rate limiting for any skill that interacts with external services:

```python
import random
import time

self.item_cooldown = config["session"]["item_cooldown_seconds"]
self.max_items = config["session"]["max_items_per_session"]

time.sleep(self.item_cooldown)

time.sleep(random.uniform(3, 7))

def _execute_with_retry(request, max_retries=5, backoff_base=2):
    for attempt in range(max_retries):
        try:
            return request.execute()
        except Exception:
            if attempt < max_retries - 1:
                time.sleep(backoff_base ** attempt)
            else:
                raise
```

---

## Pattern 11: Session Logger

**Purpose:** Structured per-session logging as newline-delimited JSON. Every skill gets this.

**Customization:** Rename `domain` parameter to match your work unit (e.g., `work_unit`, `repo`, `url`).

```python
import json
import traceback
from datetime import datetime
from pathlib import Path


class SessionLogger:
    def __init__(self, evidence_path: str):
        log_dir = Path(evidence_path) / "session_logs"
        log_dir.mkdir(parents=True, exist_ok=True)
        self.session_id = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.log_path = log_dir / f"session_{self.session_id}.jsonl"
        self._file = open(self.log_path, "a", encoding="utf-8")
        self.log_event("__session__", "started", {"session_id": self.session_id})
        print(f"Session log: {self.log_path}")

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()
        return False

    def log_event(self, work_unit: str, event: str, data: dict = None) -> None:
        """Log a structured event."""
        entry = {
            "ts": datetime.now().isoformat(),
            "work_unit": work_unit,
            "event": event,
            "data": data or {},
        }
        self._file.write(json.dumps(entry) + "\n")
        self._file.flush()

    def log_error(self, work_unit: str, error: Exception, phase: int = None) -> None:
        """Log an error with full traceback."""
        self.log_event(work_unit, "error", {
            "phase": phase,
            "error_type": type(error).__name__,
            "error_msg": str(error),
            "traceback": traceback.format_exc(),
        })

    def close(self) -> None:
        """Finalize the session log."""
        if self._file.closed:
            return
        self.log_event("__session__", "ended", {"session_id": self.session_id})
        self._file.close()
        print(f"Session log closed: {self.log_path}")

    def __del__(self):
        try:
            if hasattr(self, "_file") and not self._file.closed:
                self._file.close()
        except Exception:
            pass
```

---

## Pattern 12: Screenshot Manager

**Purpose:** Evidence capture with timestamped, step-ordered filenames per work unit.

**Customization points:**

- `STEP_ORDER` — replace with the workflow steps for your skill's domain
- `domain_dir` → rename to `unit_dir` if "domain" doesn't fit your work unit

```python
import re
from datetime import datetime
from pathlib import Path


class ScreenshotManager:
    # CUSTOMIZE: replace with your skill's workflow steps
    STEP_ORDER = [
        "initial_state",
        "form_filled",
        "pre_submit",
        "confirmation",
        "error",
    ]

    def __init__(self, evidence_root: str):
        self.evidence_root = Path(evidence_root)
        self.evidence_root.mkdir(parents=True, exist_ok=True)

    def unit_dir(self, work_unit: str) -> Path:
        """Get (or create) the evidence directory for a work unit."""
        safe = re.sub(r"[^\w\-.]", "_", work_unit)
        d = self.evidence_root / safe
        d.mkdir(parents=True, exist_ok=True)
        return d

    def screenshot_path(self, work_unit: str, step: str) -> str:
        """
        Return the full path for a screenshot file.
        Files are named: NN_stepname_HHMMSS.png where NN is the step order number.
        Unknown steps get prefix 99.
        """
        step_num = (self.STEP_ORDER.index(step) + 1) if step in self.STEP_ORDER else 99
        timestamp = datetime.now().strftime("%H%M%S")
        filename = f"{step_num:02d}_{step}_{timestamp}.png"
        return str(self.unit_dir(work_unit) / filename)

    def capture(self, browser, work_unit: str, step: str) -> tuple[str, bool]:
        """
        Capture a screenshot via the browser object and save to the evidence archive.
        Returns (path, success). Path is always set (useful for logging even on failure).
        """
        path = self.screenshot_path(work_unit, step)
        try:
            screenshot_bytes = browser.screenshot()
            Path(path).write_bytes(screenshot_bytes)
            print(f"  📷 {step}: {path}")
            return path, True
        except Exception as e:
            print(f"  ⚠  Screenshot failed ({step}): {e}")
            return path, False

    def get_evidence_paths(self, work_unit: str) -> list[str]:
        """List all screenshots for a work unit, sorted by filename."""
        return sorted(str(p) for p in self.unit_dir(work_unit).glob("*.png"))
```
