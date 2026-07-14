"""Integration tests for the bridge webhook -> DB -> worker lifecycle.

Uses a real temporary SQLite database and temp workspace root. GitHub, HUD,
workspace preparation, and subprocess execution are mocked so the suite never
uses network, secrets, or a real shft invocation.

Run: python3 -m unittest discover -s test/python -p "test_bridge_integration.py" -v
"""

import hashlib
import hmac
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from fastapi.testclient import TestClient

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT))

from bridge import db
from bridge import webhook as wh
from bridge import worker
from bridge.config import Config
from bridge.github import PrMetadata, Token, UnresolvedThread


_SECRET = "s" * 40
_TOKEN = Token(value="ghs_test", expires_at="2026-01-01T00:00:00Z")


def _copilot_review_payload() -> dict:
    return {
        "repository": {"full_name": "org/repo"},
        "review": {
            "user": {"login": "copilot-pull-request-reviewer[bot]"},
            "state": "changes_requested",
            "html_url": "https://example.test/reviews/1",
        },
        "pull_request": {"number": 7},
    }


def _sign(body: bytes) -> str:
    digest = hmac.new(_SECRET.encode(), body, hashlib.sha256).hexdigest()
    return f"sha256={digest}"


class TestBridgeWebhookWorkerIntegration(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.db_path = self.root / "state.db"
        self.workspaces_root = self.root / "workspaces"
        self.cfg = Config(
            github_app_id="app-id",
            github_app_installation_id="install-id",
            webhook_secret=_SECRET,
            webhook_port=8765,
            copilot_bot_login="copilot-pull-request-reviewer[bot]",
            repo_allowlist=("org/repo",),
            max_iterations=3,
            worker_count=1,
            dotfiles_root=self.root / "dotfiles",
            bridge_root=self.root,
            workspaces_root=self.workspaces_root,
            db_path=self.db_path,
            log_path=self.root / "logs" / "bridge.log",
            mint_script=self.root / "mint.py",
            hud_script=self.root / "hud.sh",
        )
        db.init_db(self.db_path)

        self._orig_config = wh.config
        self._orig_secret = wh._webhook_secret
        wh.config = self.cfg
        wh._webhook_secret = _SECRET
        self.addCleanup(setattr, wh, "config", self._orig_config)
        self.addCleanup(setattr, wh, "_webhook_secret", self._orig_secret)

        self.client = TestClient(wh.app)
        self.addCleanup(self.client.close)

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def _post_review(self, delivery_id: str = "delivery-1"):
        body = json.dumps(_copilot_review_payload()).encode()
        return self.client.post(
            "/webhook",
            content=body,
            headers={
                "X-GitHub-Event": "pull_request_review",
                "X-GitHub-Delivery": delivery_id,
                "X-Hub-Signature-256": _sign(body),
            },
        )

    def test_valid_review_delivery_processes_one_job_to_done(self):
        response = self._post_review()
        self.assertEqual(response.status_code, 202)

        with db.connect(self.db_path) as conn:
            queued = conn.execute("SELECT * FROM jobs").fetchall()
        self.assertEqual(len(queued), 1)
        self.assertEqual(queued[0]["status"], "queued")

        thread = UnresolvedThread(
            thread_id="thread-1",
            url="https://example.test/thread",
            path="bridge/worker.py",
            line=12,
            body="fix this",
            diff_hunk=None,
            author="copilot-pull-request-reviewer[bot]",
        )
        ws_path = self.workspaces_root / "org--repo--pr7"

        def prepare_workspace(*_args, **_kwargs):
            ws_path.mkdir(parents=True, exist_ok=True)
            return ws_path

        with mock.patch("bridge.worker.hud.emit"), \
                mock.patch("bridge.worker.github.mint_token", return_value=_TOKEN), \
                mock.patch(
                    "bridge.worker.github.fetch_unresolved_copilot_threads",
                    return_value=[thread],
                ), \
                mock.patch("bridge.worker.github.find_tracking_issue", return_value=None), \
                mock.patch(
                    "bridge.worker.github.fetch_pr_metadata",
                    return_value=PrMetadata(
                        head_ref="feature",
                        head_repo_full_name="org/repo",
                        title="Test PR",
                        html_url="https://example.test/pulls/7",
                    ),
                ), \
                mock.patch("bridge.worker.workspace.prepare", side_effect=prepare_workspace), \
                mock.patch("bridge.worker.github.create_issue", return_value=123), \
                mock.patch("bridge.worker._run_subprocess") as run_subprocess:
            processed = worker.process_one_job(self.cfg, "worker-1")

        self.assertTrue(processed)
        run_subprocess.assert_called_once()

        with db.connect(self.db_path) as conn:
            row = conn.execute("SELECT * FROM jobs").fetchone()
            iteration = db.read_iteration(conn, "org/repo#7")

        self.assertEqual(row["status"], "done")
        self.assertEqual(row["tracking_issue_number"], 123)
        self.assertEqual(row["workspace_path"], str(ws_path))
        self.assertEqual(row["iteration"], 1)
        self.assertEqual(iteration, 1)
        self.assertFalse(ws_path.exists())


if __name__ == "__main__":
    unittest.main()
