"""Unit tests for bridge DB migration system.

Covers: schema versioning, upgrading old DBs missing columns/tables,
and verifying current queries work after migration.

Run: python3 -m unittest discover -s test/python -p "test_bridge_migrations.py" -v
"""

import shutil
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT))

from bridge import db


def _make_tmp():
    tmp_dir = tempfile.mkdtemp()
    tmp = Path(tmp_dir) / "test.db"
    return tmp, tmp_dir


# The "v0" schema: jobs table without claim_keys table and without some columns.
# This simulates a DB created before claim_keys and iteration tracking existed.
V0_SCHEMA = """
CREATE TABLE jobs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  delivery_id TEXT UNIQUE NOT NULL,
  event_type TEXT NOT NULL,
  repo_full_name TEXT NOT NULL,
  pr_number INTEGER NOT NULL,
  payload_json TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'queued',
  enqueued_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  claimed_at TIMESTAMP,
  finished_at TIMESTAMP
);
"""


# The "v1" schema: has jobs with claim_key but no claim_keys table, no iteration,
# no tracking_issue_number, no workspace_path, no worker_id, no error columns.
V1_SCHEMA = """
CREATE TABLE jobs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  delivery_id TEXT UNIQUE NOT NULL,
  event_type TEXT NOT NULL,
  repo_full_name TEXT NOT NULL,
  pr_number INTEGER NOT NULL,
  claim_key TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'queued',
  enqueued_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  claimed_at TIMESTAMP,
  finished_at TIMESTAMP
);
"""


class TestSchemaVersionTracking(unittest.TestCase):
    """Schema version tracking exists after init."""

    def setUp(self):
        self.db_path, self._tmpdir = _make_tmp()

    def tearDown(self):
        shutil.rmtree(self._tmpdir, ignore_errors=True)

    def test_fresh_db_has_schema_version(self):
        db.init_db(self.db_path)
        with db.connect(self.db_path) as conn:
            row = conn.execute(
                "SELECT version FROM schema_version"
            ).fetchone()
            self.assertIsNotNone(row)
            self.assertEqual(row["version"], db.CURRENT_SCHEMA_VERSION)

    def test_reinit_does_not_downgrade(self):
        db.init_db(self.db_path)
        with db.connect(self.db_path) as conn:
            # Artificially bump version
            conn.execute("UPDATE schema_version SET version = 999")
        db.init_db(self.db_path)
        with db.connect(self.db_path) as conn:
            row = conn.execute("SELECT version FROM schema_version").fetchone()
            self.assertEqual(row["version"], 999)


class TestMigrateV0(unittest.TestCase):
    """Old DB missing claim_key column, claim_keys table, and other columns upgrades."""

    def setUp(self):
        self.db_path, self._tmpdir = _make_tmp()
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        with sqlite3.connect(self.db_path) as conn:
            conn.executescript(V0_SCHEMA)

    def tearDown(self):
        shutil.rmtree(self._tmpdir, ignore_errors=True)

    def test_init_upgrades_v0(self):
        db.init_db(self.db_path)
        with db.connect(self.db_path) as conn:
            # Should now have claim_keys table
            row = conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='claim_keys'"
            ).fetchone()
            self.assertIsNotNone(row)
            # Should have claim_key column in jobs
            cols = {r[1] for r in conn.execute("PRAGMA table_info(jobs)").fetchall()}
            self.assertIn("claim_key", cols)
            self.assertIn("iteration", cols)
            self.assertIn("tracking_issue_number", cols)
            self.assertIn("workspace_path", cols)
            self.assertIn("worker_id", cols)
            self.assertIn("error", cols)

    def test_existing_data_preserved(self):
        # Insert a row in v0 format
        with sqlite3.connect(self.db_path) as conn:
            conn.execute(
                "INSERT INTO jobs (delivery_id, event_type, repo_full_name, pr_number, payload_json)"
                " VALUES ('d-old', 'pull_request_review', 'org/repo', 1, '{}')"
            )
        db.init_db(self.db_path)
        with db.connect(self.db_path) as conn:
            row = conn.execute("SELECT * FROM jobs WHERE delivery_id='d-old'").fetchone()
            self.assertIsNotNone(row)
            self.assertEqual(row["repo_full_name"], "org/repo")

    def test_current_queries_work_after_migration(self):
        """Full enqueue/claim/done cycle works on migrated DB."""
        db.init_db(self.db_path)
        with db.connect(self.db_path) as conn:
            inserted = db.enqueue(
                conn,
                delivery_id="d-new",
                event_type="pull_request_review",
                repo_full_name="org/repo",
                pr_number=10,
                payload={"action": "submitted"},
            )
            self.assertTrue(inserted)
            job = db.claim_next_job(conn, worker_id="w-1")
            self.assertIsNotNone(job)
            self.assertEqual(job.delivery_id, "d-new")
            db.mark_done(conn, job.id, tracking_issue_number=5)
            v = db.bump_iteration(conn, "org/repo#10")
            self.assertEqual(v, 1)


class TestMigrateV1(unittest.TestCase):
    """DB with claim_key but missing claim_keys table and extra columns."""

    def setUp(self):
        self.db_path, self._tmpdir = _make_tmp()
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        with sqlite3.connect(self.db_path) as conn:
            conn.executescript(V1_SCHEMA)

    def tearDown(self):
        shutil.rmtree(self._tmpdir, ignore_errors=True)

    def test_init_upgrades_v1(self):
        db.init_db(self.db_path)
        with db.connect(self.db_path) as conn:
            row = conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='claim_keys'"
            ).fetchone()
            self.assertIsNotNone(row)
            cols = {r[1] for r in conn.execute("PRAGMA table_info(jobs)").fetchall()}
            self.assertIn("iteration", cols)
            self.assertIn("tracking_issue_number", cols)
            self.assertIn("workspace_path", cols)
            self.assertIn("worker_id", cols)
            self.assertIn("error", cols)

    def test_current_queries_work_after_migration(self):
        db.init_db(self.db_path)
        with db.connect(self.db_path) as conn:
            inserted = db.enqueue(
                conn,
                delivery_id="d-1",
                event_type="pull_request_review",
                repo_full_name="org/repo",
                pr_number=5,
                payload={},
            )
            self.assertTrue(inserted)
            job = db.claim_next_job(conn, worker_id="w-1")
            self.assertIsNotNone(job)
            db.mark_failed(conn, job.id, "oops")


if __name__ == "__main__":
    unittest.main()
