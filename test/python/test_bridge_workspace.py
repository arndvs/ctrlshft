"""Unit tests for bridge/workspace.py — workspace path derivation and the
prepare() clone/fetch/reset lifecycle with failure cleanup.

Covers: workspace_path() collision-safe derivation, prepare() happy path,
clone-failure and clone-timeout partial-clone cleanup (the disk/credential
leak the audit flagged), existing-workspace fetch+reset (no re-clone),
fetch-failure preserving the existing clone, and cleanup().

subprocess.run is mocked — no real git is invoked.

Run: python3 -m unittest discover -s test/python -p "test_bridge_workspace.py" -v
"""

import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT))

from bridge.workspace import WorkspaceError, cleanup, prepare, workspace_path
from bridge.github import Token

_TOKEN = Token(value="ghs_test", expires_at="2026-01-01T00:00:00Z")


class TestWorkspacePath(unittest.TestCase):
    def test_basic_derivation(self):
        root = Path("/ws")
        self.assertEqual(workspace_path(root, "org/repo#42"), root / "org--repo--pr42")

    def test_collision_safety(self):
        # 'a-b/c' and 'a/b-c' must not map to the same directory.
        root = Path("/ws")
        self.assertNotEqual(
            workspace_path(root, "a-b/c#1"), workspace_path(root, "a/b-c#1")
        )


class TestPrepare(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.path = workspace_path(self.root, "org/repo#7")

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def _prepare(self):
        return prepare(
            self.root, token=_TOKEN, repo_full_name="org/repo",
            pr_number=7, head_ref="main",
        )

    def test_clone_success_returns_path(self):
        def fake_run(cmd, **kw):
            if "clone" in cmd:
                Path(cmd[-1]).mkdir(parents=True, exist_ok=True)
            return subprocess.CompletedProcess(cmd, 0, "", "")

        with mock.patch("bridge.workspace.subprocess.run", side_effect=fake_run):
            p = self._prepare()
        self.assertEqual(p, self.path)
        self.assertTrue(p.exists())

    def test_clone_failure_cleans_up_partial(self):
        def fake_run(cmd, **kw):
            Path(cmd[-1]).mkdir(parents=True, exist_ok=True)  # partial clone
            raise subprocess.CalledProcessError(128, cmd, stderr="fatal: auth")

        with mock.patch("bridge.workspace.subprocess.run", side_effect=fake_run):
            with self.assertRaises(WorkspaceError):
                self._prepare()
        self.assertFalse(self.path.exists())  # partial clone removed — no disk/cred leak

    def test_clone_timeout_cleans_up_partial(self):
        def fake_run(cmd, **kw):
            Path(cmd[-1]).mkdir(parents=True, exist_ok=True)
            raise subprocess.TimeoutExpired(cmd, 300)

        with mock.patch("bridge.workspace.subprocess.run", side_effect=fake_run):
            with self.assertRaises(WorkspaceError):
                self._prepare()
        self.assertFalse(self.path.exists())

    def test_existing_workspace_fetches_not_clones(self):
        self.path.mkdir(parents=True)  # workspace already present
        calls = []

        def fake_run(cmd, **kw):
            calls.append(" ".join(cmd))
            return subprocess.CompletedProcess(cmd, 0, "", "")

        with mock.patch("bridge.workspace.subprocess.run", side_effect=fake_run):
            p = self._prepare()
        self.assertEqual(p, self.path)
        self.assertFalse(any("clone" in c for c in calls))
        self.assertTrue(any("fetch" in c for c in calls))
        self.assertTrue(any("reset --hard" in c for c in calls))

    def test_fetch_failure_preserves_existing_workspace(self):
        self.path.mkdir(parents=True)

        def fake_run(cmd, **kw):
            if "fetch" in cmd:
                raise subprocess.CalledProcessError(1, cmd)
            return subprocess.CompletedProcess(cmd, 0, "", "")

        with mock.patch("bridge.workspace.subprocess.run", side_effect=fake_run):
            with self.assertRaises(WorkspaceError):
                self._prepare()
        # A fetch/reset failure must NOT nuke the existing clone (only clone-time
        # failures clean up).
        self.assertTrue(self.path.exists())


class TestCleanup(unittest.TestCase):
    def test_removes_existing_workspace(self):
        root = Path(tempfile.mkdtemp())
        try:
            p = workspace_path(root, "org/repo#7")
            p.mkdir(parents=True)
            cleanup(root, "org/repo#7")
            self.assertFalse(p.exists())
        finally:
            shutil.rmtree(root, ignore_errors=True)

    def test_missing_workspace_is_noop(self):
        root = Path(tempfile.mkdtemp())
        try:
            cleanup(root, "org/repo#999")  # must not raise
        finally:
            shutil.rmtree(root, ignore_errors=True)


class TestPrepareShutdown(unittest.TestCase):
    """Test shutdown-aware workspace.prepare with shutdown_check callback."""

    def setUp(self):
        self.root = Path(tempfile.mkdtemp())

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def test_shutdown_during_clone_raises_workspace_error(self):
        from bridge.workspace import WorkspaceError, _run_git

        proc = mock.MagicMock()
        proc.poll.return_value = None
        proc.pid = 5678
        proc.wait.side_effect = subprocess.TimeoutExpired("cmd", 0.5)

        with mock.patch("bridge.workspace.subprocess.Popen", return_value=proc), \
                mock.patch("bridge.workspace._terminate_popen") as terminate, \
                mock.patch("bridge.workspace._time.monotonic", return_value=0):
            with self.assertRaises(WorkspaceError) as ctx:
                _run_git(
                    ["git", "clone", "--branch", "main", "url", "/path"],
                    env={},
                    timeout=300,
                    shutdown_check=lambda: True,
                )

        self.assertIn("shutdown", str(ctx.exception))
        terminate.assert_called_once_with(proc)

    def test_shutdown_during_fetch_raises_workspace_error(self):
        from bridge.workspace import WorkspaceError, _run_git

        proc = mock.MagicMock()
        proc.poll.return_value = None
        proc.pid = 5678
        proc.wait.side_effect = subprocess.TimeoutExpired("cmd", 0.5)

        with mock.patch("bridge.workspace.subprocess.Popen", return_value=proc), \
                mock.patch("bridge.workspace._terminate_popen") as terminate, \
                mock.patch("bridge.workspace._time.monotonic", return_value=0):
            with self.assertRaises(WorkspaceError) as ctx:
                _run_git(
                    ["git", "-C", "/ws", "fetch", "origin", "refs/heads/main:refs/remotes/origin/main"],
                    env={},
                    timeout=120,
                    shutdown_check=lambda: True,
                )

        self.assertIn("shutdown", str(ctx.exception))
        terminate.assert_called_once_with(proc)

    def test_run_git_completes_without_shutdown(self):
        from bridge.workspace import _run_git

        proc = mock.MagicMock()
        proc.poll.return_value = None
        proc.pid = 5678
        proc.returncode = 0
        proc.stdout.read.return_value = ""
        proc.stderr.read.return_value = ""
        proc.wait.return_value = None

        with mock.patch("bridge.workspace.subprocess.Popen", return_value=proc), \
                mock.patch("bridge.workspace._time.monotonic", return_value=0):
            result = _run_git(
                ["git", "status"],
                env={},
                timeout=30,
                shutdown_check=lambda: False,
            )

        self.assertEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
