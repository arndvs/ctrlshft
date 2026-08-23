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

        self._hud_patch = mock.patch("bridge.webhook.hud.emit")
        self.hud_emit = self._hud_patch.start()
        self.addCleanup(self._hud_patch.stop)

        self.client = TestClient(wh.app)
        self.addCleanup(self.client.close)

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def _post_payload(
        self,
        payload: dict,
        *,
        delivery_id: str = "delivery-1",
        event: str = "pull_request_review",
        sig: str = "__valid__",
    ):
        body = json.dumps(payload).encode()
        headers = {
            "X-GitHub-Event": event,
            "X-GitHub-Delivery": delivery_id,
        }
        if sig == "__valid__":
            headers["X-Hub-Signature-256"] = _sign(body)
        elif sig is not None:
            headers["X-Hub-Signature-256"] = sig
        return self.client.post(
            "/webhook",
            content=body,
            headers=headers,
        )

    def _post_review(self, delivery_id: str = "delivery-1"):
        return self._post_payload(_copilot_review_payload(), delivery_id=delivery_id)

    def _job_count(self) -> int:
        with db.connect(self.db_path) as conn:
            return conn.execute("SELECT COUNT(*) FROM jobs").fetchone()[0]

    def test_valid_review_delivery_processes_one_job_to_done(self):
        response = self._post_review()
        self.assertEqual(response.status_code, 202)
        self.hud_emit.assert_called_once()
        self.assertEqual(self.hud_emit.call_args.args[1], "bridge.webhook.received")

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

    def test_duplicate_delivery_is_idempotent_in_real_db(self):
        first = self._post_review(delivery_id="delivery-dup")
        second = self._post_review(delivery_id="delivery-dup")

        self.assertEqual(first.status_code, 202)
        self.assertEqual(second.status_code, 202)

        with db.connect(self.db_path) as conn:
            rows = conn.execute(
                "SELECT * FROM jobs WHERE delivery_id='delivery-dup'"
            ).fetchall()

        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["status"], "queued")
        self.hud_emit.assert_called_once()
        self.assertEqual(self.hud_emit.call_args.args[1], "bridge.webhook.received")

    def test_rejected_webhook_events_do_not_enqueue_jobs(self):
        cases = [
            (
                "bad signature",
                _copilot_review_payload(),
                {"sig": "sha256=bad"},
                401,
            ),
            (
                "disallowed event",
                _copilot_review_payload(),
                {"event": "push"},
                204,
            ),
            (
                "non-allowlisted repo",
                {
                    **_copilot_review_payload(),
                    "repository": {"full_name": "evil/repo"},
                },
                {},
                204,
            ),
            (
                "non-copilot actor",
                {
                    **_copilot_review_payload(),
                    "review": {
                        **_copilot_review_payload()["review"],
                        "user": {"login": "human-reviewer"},
                    },
                },
                {},
                204,
            ),
            (
                "non-changes-requested review",
                {
                    **_copilot_review_payload(),
                    "review": {
                        **_copilot_review_payload()["review"],
                        "state": "approved",
                    },
                },
                {},
                204,
            ),
        ]

        for index, (name, payload, kwargs, expected_status) in enumerate(cases, 1):
            with self.subTest(name=name):
                response = self._post_payload(
                    payload,
                    delivery_id=f"rejected-{index}",
                    **kwargs,
                )
                self.assertEqual(response.status_code, expected_status)
                self.assertEqual(self._job_count(), 0)

        self.assertFalse(
            any(call.args[1] == "bridge.webhook.received" for call in self.hud_emit.call_args_list)
        )

    def test_dispatch_failure_marks_failed_without_burning_iteration(self):
        response = self._post_review()
        self.assertEqual(response.status_code, 202)
        self.hud_emit.reset_mock()

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

        def fail_job_failed_hud(_script, event, **_kwargs):
            if event == "bridge.job.failed":
                raise RuntimeError("hud failed")

        self.hud_emit.side_effect = fail_job_failed_hud
        with mock.patch("bridge.worker.github.mint_token", return_value=_TOKEN), \
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
                mock.patch(
                    "bridge.worker._run_subprocess",
                    side_effect=RuntimeError("dispatch failed"),
                ), \
                mock.patch("bridge.worker.logger.error"), \
                mock.patch("bridge.worker.logger.warning") as warning:
            processed = worker.process_one_job(self.cfg, "worker-1")

        self.assertTrue(processed)
        self.assertGreaterEqual(warning.call_count, 1)

        with db.connect(self.db_path) as conn:
            row = conn.execute("SELECT * FROM jobs").fetchone()
            iteration = db.read_iteration(conn, "org/repo#7")

        # First dispatch failure is retryable (backoff), not terminal failed.
        self.assertEqual(row["status"], "retryable")
        self.assertEqual(row["retry_count"], 1)
        self.assertIsNotNone(row["retry_at"])
        self.assertIn("dispatch failed", row["error"])
        self.assertEqual(row["tracking_issue_number"], 123)
        self.assertEqual(row["workspace_path"], str(ws_path))
        self.assertEqual(row["iteration"], 0)
        self.assertEqual(iteration, 0)
        self.assertFalse(ws_path.exists())

        emitted_events = [call.args[1] for call in self.hud_emit.call_args_list]
        self.assertIn("bridge.job.retryable", emitted_events)
        self.assertIn("bridge.workspace.cleaned", emitted_events)

    def test_worker_startup_requeues_stale_claim_and_reaps_orphan_workspace(self):
        response = self._post_review()
        self.assertEqual(response.status_code, 202)

        with db.connect(self.db_path) as conn:
            claimed = db.claim_next_job(conn, "stale-worker")
            conn.execute(
                "UPDATE jobs SET claimed_at=datetime('now', '-3600 seconds') WHERE id=?",
                (claimed.id,),
            )

        active_workspace = self.workspaces_root / "org--repo--pr7"
        orphan_workspace = self.workspaces_root / "org--repo--pr999"
        active_workspace.mkdir(parents=True)
        orphan_workspace.mkdir(parents=True)

        cfg = mock.MagicMock()
        cfg.db_path = self.db_path
        cfg.workspaces_root = self.workspaces_root

        with mock.patch("bridge.worker.Config.from_env", return_value=cfg), \
                mock.patch.object(cfg, "require_github_app"), \
                mock.patch.object(cfg, "ensure_dirs"), \
                mock.patch("bridge.worker.process_one_job", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                worker.run("worker-1")

        with db.connect(self.db_path) as conn:
            row = conn.execute("SELECT * FROM jobs").fetchone()

        self.assertEqual(row["status"], "queued")
        self.assertIsNone(row["worker_id"])
        self.assertTrue(active_workspace.exists())
        self.assertFalse(orphan_workspace.exists())


if __name__ == "__main__":
    unittest.main()
