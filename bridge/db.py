"""SQLite-backed job queue and audit log.

Schema is forward-compatible with Phase 2 multi-worker. The MVP claim
query ignores claim_key for serialization; Phase 2 adds a NOT IN filter
in claim_next_job. Everything else is identical.
"""
from __future__ import annotations

import json
import sqlite3
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator, Optional


CURRENT_SCHEMA_VERSION = 4

SCHEMA = """
CREATE TABLE IF NOT EXISTS schema_version (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  version INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS jobs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  delivery_id TEXT UNIQUE NOT NULL,
  event_type TEXT NOT NULL,
  repo_full_name TEXT NOT NULL,
  pr_number INTEGER NOT NULL,
  claim_key TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'queued',
  iteration INTEGER NOT NULL DEFAULT 0,
  tracking_issue_number INTEGER,
  workspace_path TEXT,
  worker_id TEXT,
  error TEXT,
  retry_count INTEGER NOT NULL DEFAULT 0,
  retry_at TIMESTAMP,
  enqueued_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  claimed_at TIMESTAMP,
  finished_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS runs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  job_id INTEGER NOT NULL,
  worker_id TEXT,
  status TEXT NOT NULL DEFAULT 'in_progress',
  total_cost_usd REAL NOT NULL DEFAULT 0.0,
  started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  finished_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS steps (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id INTEGER NOT NULL,
  step_name TEXT NOT NULL,
  cost_usd REAL NOT NULL DEFAULT 0.0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS claim_keys (
  claim_key TEXT PRIMARY KEY,
  current_iteration INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_jobs_status_id ON jobs(status, id);
CREATE INDEX IF NOT EXISTS idx_jobs_claim_key ON jobs(claim_key, status);
CREATE INDEX IF NOT EXISTS idx_jobs_pr ON jobs(repo_full_name, pr_number);
"""


# Phase 2 toggle. When True, the claim query filters out any claim_key
# already held by another worker, enabling parallel processing across
# different PRs. Enabled — PR-scoped locks make concurrent claims safe.
PHASE_2_CONCURRENT_CLAIMS = True


@dataclass
class Job:
    id: int
    delivery_id: str
    event_type: str
    repo_full_name: str
    pr_number: int
    claim_key: str
    payload: dict
    status: str
    iteration: int
    tracking_issue_number: Optional[int]
    workspace_path: Optional[str]
    worker_id: Optional[str]
    retry_count: int = 0
    retry_at: Optional[str] = None

    @classmethod
    def from_row(cls, row: sqlite3.Row) -> Job:
        return cls(
            id=row["id"],
            delivery_id=row["delivery_id"],
            event_type=row["event_type"],
            repo_full_name=row["repo_full_name"],
            pr_number=row["pr_number"],
            claim_key=row["claim_key"],
            payload=json.loads(row["payload_json"]),
            status=row["status"],
            iteration=row["iteration"],
            tracking_issue_number=row["tracking_issue_number"],
            workspace_path=row["workspace_path"],
            worker_id=row["worker_id"],
            retry_count=row["retry_count"] if "retry_count" in row.keys() else 0,
            retry_at=row["retry_at"] if "retry_at" in row.keys() else None,
        )


def _get_existing_columns(conn: sqlite3.Connection, table: str) -> set:
    """Return set of column names for a table."""
    rows = conn.execute(f"PRAGMA table_info({table})").fetchall()
    return {r[1] for r in rows}


def _table_exists(conn: sqlite3.Connection, table: str) -> bool:
    row = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        (table,),
    ).fetchone()
    return row is not None


def _migrate(conn: sqlite3.Connection) -> None:
    """Upgrade an existing DB to the current schema in place."""
    # Ensure schema_version table exists
    conn.execute("""
        CREATE TABLE IF NOT EXISTS schema_version (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          version INTEGER NOT NULL
        )
    """)

    row = conn.execute("SELECT version FROM schema_version WHERE id=1").fetchone()
    if row and row[0] >= CURRENT_SCHEMA_VERSION:
        return  # Already up to date or ahead

    # --- Migration: ensure jobs table has all expected columns ---
    if _table_exists(conn, "jobs"):
        existing = _get_existing_columns(conn, "jobs")
        migrations = [
            ("claim_key", "TEXT NOT NULL DEFAULT ''"),
            ("iteration", "INTEGER NOT NULL DEFAULT 0"),
            ("tracking_issue_number", "INTEGER"),
            ("workspace_path", "TEXT"),
            ("worker_id", "TEXT"),
            ("error", "TEXT"),
            ("retry_count", "INTEGER NOT NULL DEFAULT 0"),
            ("retry_at", "TIMESTAMP"),
        ]
        for col, typedef in migrations:
            if col not in existing:
                conn.execute(f"ALTER TABLE jobs ADD COLUMN {col} {typedef}")

        conn.execute(
            "UPDATE jobs SET claim_key = repo_full_name || '#' || pr_number "
            "WHERE claim_key IS NULL OR claim_key = ''"
        )

    # --- Migration: ensure claim_keys table exists ---
    conn.execute("""
        CREATE TABLE IF NOT EXISTS claim_keys (
          claim_key TEXT PRIMARY KEY,
          current_iteration INTEGER NOT NULL DEFAULT 0,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    if _table_exists(conn, "jobs"):
        conn.execute(
            """
            INSERT OR IGNORE INTO claim_keys (claim_key)
            SELECT DISTINCT claim_key FROM jobs
              WHERE claim_key IS NOT NULL AND claim_key != ''
            """
        )

    # --- Ensure indexes ---
    conn.execute("CREATE INDEX IF NOT EXISTS idx_jobs_status_id ON jobs(status, id)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_jobs_claim_key ON jobs(claim_key, status)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_jobs_pr ON jobs(repo_full_name, pr_number)")

    # --- Set version ---
    conn.execute(
        "INSERT OR REPLACE INTO schema_version (id, version) VALUES (1, ?)",
        (CURRENT_SCHEMA_VERSION,),
    )


def init_db(db_path: Path) -> None:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(db_path) as conn:
        # PRAGMAs must run outside any transaction
        conn.execute("PRAGMA journal_mode=WAL;")
        conn.execute("PRAGMA synchronous=NORMAL;")
        # Migrate existing DBs before applying full schema
        if _table_exists(conn, "jobs"):
            _migrate(conn)
        conn.executescript(SCHEMA)
        # Set version for fresh DBs
        conn.execute(
            "INSERT OR IGNORE INTO schema_version (id, version) VALUES (1, ?)",
            (CURRENT_SCHEMA_VERSION,),
        )


@contextmanager
def connect(db_path: Path) -> Iterator[sqlite3.Connection]:
    conn = sqlite3.connect(db_path, isolation_level=None, timeout=30.0)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
    finally:
        conn.close()


def enqueue(
    conn: sqlite3.Connection,
    *,
    delivery_id: str,
    event_type: str,
    repo_full_name: str,
    pr_number: int,
    payload: dict,
) -> bool:
    """Insert a job. Returns True if inserted, False if duplicate.

    Idempotent on delivery_id — GitHub redeliveries are silently ignored.
    """
    claim_key = f"{repo_full_name}#{pr_number}"
    cur = conn.execute(
        """
        INSERT OR IGNORE INTO jobs
          (delivery_id, event_type, repo_full_name, pr_number,
           claim_key, payload_json)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        (
            delivery_id,
            event_type,
            repo_full_name,
            pr_number,
            claim_key,
            json.dumps(payload),
        ),
    )
    if cur.rowcount > 0:
        # Ensure claim_key row exists for iteration tracking
        conn.execute(
            "INSERT OR IGNORE INTO claim_keys (claim_key) VALUES (?)",
            (claim_key,),
        )
    return cur.rowcount > 0


def claim_next_job(conn: sqlite3.Connection, worker_id: str) -> Optional[Job]:
    """Atomically claim the next claimable job.

    Claims the oldest queued job, or a retryable job whose retry_at has
    passed. With PHASE_2_CONCURRENT_CLAIMS, skips jobs whose claim_key is
    already held by another worker (parallel processing across PRs).
    """
    conn.execute("BEGIN IMMEDIATE;")
    try:
        if PHASE_2_CONCURRENT_CLAIMS:
            row = conn.execute(
                """
                SELECT * FROM jobs
                  WHERE status = 'queued'
                    AND claim_key NOT IN (
                      SELECT claim_key FROM jobs WHERE status = 'claimed'
                    )
                  ORDER BY id
                  LIMIT 1
                """
            ).fetchone()
        else:
            row = conn.execute(
                """
                SELECT * FROM jobs
                  WHERE status = 'queued'
                  ORDER BY id
                  LIMIT 1
                """
            ).fetchone()

        if row is None:
            # No queued job — check for a retryable job whose retry_at has passed.
            retry_row = conn.execute(
                """
                SELECT * FROM jobs
                  WHERE status = 'retryable'
                    AND (retry_at IS NULL OR retry_at <= datetime('now'))
                  ORDER BY id
                  LIMIT 1
                """
            ).fetchone()
            if retry_row is not None:
                row = retry_row

        if row is None:
            conn.execute("COMMIT;")
            return None

        conn.execute(
            """
            UPDATE jobs
              SET status='claimed',
                  claimed_at=CURRENT_TIMESTAMP,
                  worker_id=?
              WHERE id=?
            """,
            (worker_id, row["id"]),
        )
        conn.execute("COMMIT;")
        row = conn.execute(
            "SELECT * FROM jobs WHERE id=?", (row["id"],)
        ).fetchone()
        return Job.from_row(row)
    except Exception:
        conn.execute("ROLLBACK;")
        raise


def mark_done(
    conn: sqlite3.Connection,
    job_id: int,
    *,
    tracking_issue_number: Optional[int] = None,
    workspace_path: Optional[str] = None,
) -> None:
    conn.execute(
        """
        UPDATE jobs
          SET status='done',
              finished_at=CURRENT_TIMESTAMP,
              tracking_issue_number=COALESCE(?, tracking_issue_number),
              workspace_path=COALESCE(?, workspace_path)
          WHERE id=?
        """,
        (tracking_issue_number, workspace_path, job_id),
    )


def mark_failed(conn: sqlite3.Connection, job_id: int, error: str) -> None:
    conn.execute(
        """
        UPDATE jobs
          SET status='failed',
              finished_at=CURRENT_TIMESTAMP,
              error=?
          WHERE id=?
        """,
        (error[:4000], job_id),
    )


def mark_retryable(
    conn: sqlite3.Connection,
    job_id: int,
    error: str,
    *,
    retry_count: int,
    retry_at: Optional[str] = None,
) -> None:
    """Mark a job retryable with a backoff retry_at timestamp.

    The job returns to the claimable pool once retry_at passes. retry_count
    is the attempt number (1-based) that just failed.
    """
    conn.execute(
        """
        UPDATE jobs
          SET status='retryable',
              error=?,
              retry_count=?,
              retry_at=?,
              finished_at=NULL
          WHERE id=?
        """,
        (error[:4000], retry_count, retry_at, job_id),
    )


def bump_iteration(conn: sqlite3.Connection, claim_key: str) -> int:
    """Increment the per-PR iteration counter and return new value.

    Uses the dedicated claim_keys table (fixes H-4 from audit —
    iteration count is independent of job volume).

    Ensures the claim_key row exists first (UPSERT guard) so the
    function is robust to partial/older DB state.
    """
    conn.execute(
        "INSERT OR IGNORE INTO claim_keys (claim_key) VALUES (?)",
        (claim_key,),
    )
    conn.execute(
        """
        UPDATE claim_keys
          SET current_iteration = current_iteration + 1
          WHERE claim_key = ?
        """,
        (claim_key,),
    )
    row = conn.execute(
        "SELECT current_iteration FROM claim_keys WHERE claim_key = ?",
        (claim_key,),
    ).fetchone()
    return row["current_iteration"]


def read_iteration(conn: sqlite3.Connection, claim_key: str) -> int:
    """Return the current iteration count without incrementing.

    Returns 0 if no row exists yet (first time seeing this claim_key).
    """
    row = conn.execute(
        "SELECT current_iteration FROM claim_keys WHERE claim_key = ?",
        (claim_key,),
    ).fetchone()
    return row["current_iteration"] if row else 0


def requeue_stale_claims(
    conn: sqlite3.Connection,
    timeout_seconds: int = 1800,
) -> int:
    """Requeue jobs stuck in 'claimed' state beyond the lease timeout.

    Returns the number of requeued jobs.
    """
    cursor = conn.execute(
        """
        UPDATE jobs
          SET status='queued',
              claimed_at=NULL,
              worker_id=NULL
          WHERE status='claimed'
            AND claimed_at < datetime('now', ? || ' seconds')
        """,
        (f"-{timeout_seconds}",),
    )
    return cursor.rowcount


# ── Run/step store (orchestrator seed) ───────────────────────────────────────

def create_run(
    conn: sqlite3.Connection,
    job_id: int,
    *,
    worker_id: str,
) -> int:
    """Create a parent run row for a claimed job. Returns the run id."""
    cur = conn.execute(
        """
        INSERT INTO runs (job_id, worker_id, status)
        VALUES (?, ?, 'in_progress')
        """,
        (job_id, worker_id),
    )
    return cur.lastrowid


def append_step(
    conn: sqlite3.Connection,
    run_id: int,
    step_name: str,
    *,
    cost_usd: float = 0.0,
) -> None:
    """Append a step row to a run, accumulating cost."""
    conn.execute(
        """
        INSERT INTO steps (run_id, step_name, cost_usd)
        VALUES (?, ?, ?)
        """,
        (run_id, step_name, cost_usd),
    )
    conn.execute(
        """
        UPDATE runs
          SET total_cost_usd = total_cost_usd + ?
          WHERE id = ?
        """,
        (cost_usd, run_id),
    )


def complete_run(
    conn: sqlite3.Connection,
    run_id: int,
    *,
    status: str,
) -> None:
    """Mark a run complete with a terminal status."""
    conn.execute(
        """
        UPDATE runs
          SET status=?, finished_at=CURRENT_TIMESTAMP
          WHERE id=?
        """,
        (status, run_id),
    )


def get_run_steps(conn: sqlite3.Connection, run_id: int) -> list[dict]:
    """Return all steps for a run, oldest first."""
    rows = conn.execute(
        """
        SELECT * FROM steps WHERE run_id=? ORDER BY id
        """,
        (run_id,),
    ).fetchall()
    return [dict(r) for r in rows]


def fetch_runs_for_job(conn: sqlite3.Connection, job_id: int) -> list[dict]:
    """Return all runs for a job, oldest first."""
    rows = conn.execute(
        """
        SELECT * FROM runs WHERE job_id=? ORDER BY id
        """,
        (job_id,),
    ).fetchall()
    return [dict(r) for r in rows]
