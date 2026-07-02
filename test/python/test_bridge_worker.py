"""Unit tests for bridge/worker.py — subprocess env, process-group cleanup,
and workflow dispatch command construction.

subprocess.Popen, os.killpg/os.getpgid, and signal are mocked (the latter with
create=True so the suite runs on platforms without POSIX process-group APIs).
No real process is spawned.

Covers: _build_subprocess_env() credential/GH env, _run_subprocess() success /
non-zero / timeout-SIGTERM / timeout-SIGKILL escalation (the orphaned-process
risk the audit flagged), and _dispatch_* command construction.

Run: python3 -m unittest discover -s test/python -p "test_bridge_worker.py" -v
"""

import os
import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT))

from bridge.worker import (
    _build_subprocess_env,
    _dispatch_address_review,
    _dispatch_shft_afk,
    _run_subprocess,
)
from bridge.github import Token

_TOKEN = Token(value="ghs_test", expires_at="2026-01-01T00:00:00Z")


class TestBuildSubprocessEnv(unittest.TestCase):
    def _build(self):
        return _build_subprocess_env(
            mock.MagicMock(), _TOKEN, Path("/ws"), "org/repo"
        )

    def test_sets_gh_and_workspace_vars(self):
        with mock.patch.dict(os.environ, {"HOME": "/home/x", "PATH": "/usr/bin",
                                          "TERM": "xterm", "LANG": "C", "USER": "u"}, clear=True):
            env = self._build()
        self.assertEqual(env["GH_TOKEN"], "ghs_test")
        self.assertEqual(env["GH_REPO"], "org/repo")
        self.assertEqual(env["BRIDGE_WORKSPACE"], str(Path("/ws")))

    def test_injects_git_credentials(self):
        with mock.patch.dict(os.environ, {"HOME": "/home/x", "PATH": "/usr/bin"}, clear=True):
            env = self._build()
        self.assertEqual(env["GIT_CONFIG_COUNT"], "1")
        self.assertIn("x-access-token:ghs_test@github.com", env["GIT_CONFIG_KEY_0"])

    def test_prepends_local_bin_to_path(self):
        # worker.py runs only on POSIX (it uses os.killpg/SIGKILL), so it joins
        # PATH with a literal ':' — pin that exact contract rather than a loose
        # startswith. USERPROFILE is set so ~ expands the same way the code sees
        # it on Windows (USERPROFILE) and POSIX (HOME).
        home = "/home/x"
        with mock.patch.dict(os.environ, {"HOME": home, "USERPROFILE": home,
                                          "PATH": "/usr/bin"}, clear=True):
            local_bin = os.path.expanduser("~/.local/bin")
            env = self._build()
        self.assertEqual(env["PATH"], f"{local_bin}:/usr/bin")

    def test_does_not_duplicate_local_bin_when_already_present(self):
        # The else branch: when ~/.local/bin is already on PATH (membership
        # tested via split(':')), PATH is returned unchanged — no duplicate
        # prepend. This locks in the ':' separator from the other direction.
        home = "/home/x"
        with mock.patch.dict(os.environ, {"HOME": home, "USERPROFILE": home,
                                          "PATH": "/tmp"}, clear=True):
            local_bin = os.path.expanduser("~/.local/bin")
        with mock.patch.dict(os.environ, {"HOME": home, "USERPROFILE": home,
                                          "PATH": f"{local_bin}:/usr/bin"}, clear=True):
            env = self._build()
        self.assertEqual(env["PATH"], f"{local_bin}:/usr/bin")

    def test_does_not_leak_unsafe_env(self):
        with mock.patch.dict(os.environ, {"HOME": "/home/x", "PATH": "/usr/bin",
                                          "AWS_SECRET_ACCESS_KEY": "leak"}, clear=True):
            env = self._build()
        self.assertNotIn("AWS_SECRET_ACCESS_KEY", env)


def _proc(returncode=0, wait_side_effect=None, pid=4321):
    p = mock.MagicMock()
    p.pid = pid
    p.returncode = returncode
    if wait_side_effect is not None:
        p.wait.side_effect = wait_side_effect
    else:
        p.wait.return_value = returncode
    return p


class TestRunSubprocess(unittest.TestCase):
    def _run(self, proc):
        emit = mock.MagicMock()
        with mock.patch("bridge.worker.subprocess.Popen", return_value=proc) as popen, \
                mock.patch("bridge.worker.os.getpgid", return_value=proc.pid, create=True), \
                mock.patch("bridge.worker.os.killpg", create=True) as killpg, \
                mock.patch("bridge.worker.signal.SIGKILL", 9, create=True):
            ctx = mock.patch("bridge.worker.signal.SIGTERM", 15, create=True)
            with ctx:
                try:
                    _run_subprocess(["shft", "afk", "1"], cwd=".", env={}, emit=emit)
                    raised = None
                except RuntimeError as e:
                    raised = e
        self.popen = popen
        return raised, killpg, emit

    def test_success_emits_and_no_raise(self):
        raised, killpg, emit = self._run(_proc(returncode=0))
        self.assertIsNone(raised)
        killpg.assert_not_called()
        emit.assert_any_call("bridge.job.shft_completed", exit_code=0)

    def test_popen_starts_new_session(self):
        # start_new_session=True puts the child in its own process group, so the
        # killpg() timeout cleanup targets the child's group — not the worker's
        # own group (which would signal the worker itself). Pin the full call so
        # a regression dropping the flag is caught here.
        self._run(_proc(returncode=0))
        self.popen.assert_called_once_with(
            ["shft", "afk", "1"], cwd=".", env={}, start_new_session=True
        )

    def test_nonzero_exit_raises(self):
        raised, killpg, emit = self._run(_proc(returncode=1))
        self.assertIsInstance(raised, RuntimeError)
        killpg.assert_not_called()

    def test_timeout_sigterm_kills_process_group(self):
        # First wait times out; the post-SIGTERM wait returns rc 0 (Popen.wait()
        # returns an int) → exactly one killpg targeting the child's process
        # group (pid 4321) with SIGTERM (15), not the bare pid and not SIGKILL.
        # Asserting the args (not just the count) enforces SIGTERM-first behavior.
        proc = _proc(wait_side_effect=[subprocess.TimeoutExpired("cmd", 1), 0])
        raised, killpg, emit = self._run(proc)
        self.assertIsInstance(raised, RuntimeError)
        killpg.assert_called_once_with(4321, 15)
        emit.assert_any_call("bridge.job.failed", reason="subprocess_timeout")

    def test_timeout_escalates_to_sigkill(self):
        # Initial wait + the SIGTERM wait both time out → ordered escalation:
        # SIGTERM (15) then SIGKILL (9) on the same process group, no extra or
        # reordered calls. The exact call list catches double-SIGKILL or
        # SIGKILL-before-SIGTERM regressions that a bare count would miss.
        proc = _proc(wait_side_effect=[
            subprocess.TimeoutExpired("cmd", 1),
            subprocess.TimeoutExpired("cmd", 1),
            0,  # post-SIGKILL wait returns rc 0 (Popen.wait() returns an int)
        ])
        raised, killpg, emit = self._run(proc)
        self.assertIsInstance(raised, RuntimeError)
        self.assertEqual(
            killpg.call_args_list, [mock.call(4321, 15), mock.call(4321, 9)]
        )


class TestDispatch(unittest.TestCase):
    def _capture_cmd(self, dispatch_fn, **kwargs):
        captured = {}

        def fake_run(cmd, cwd, env, emit):
            captured["cmd"] = cmd

        cfg = mock.MagicMock()
        cfg.dotfiles_root = Path("/df")
        with mock.patch("bridge.worker._run_subprocess", side_effect=fake_run):
            dispatch_fn(cfg=cfg, ws_path=Path("/ws"), env={}, emit=mock.MagicMock(), **kwargs)
        return captured["cmd"]

    def test_address_review_cmd(self):
        # Pin the exact executable + argument ordering the engine expects, not
        # just membership — a reordered, renamed, or dropped argv must fail here.
        engine_main = str(Path("/df") / "shft" / "engine" / "main.ts")
        cmd = self._capture_cmd(
            _dispatch_address_review, pr_number=7, iteration_num=2, max_iterations=3
        )
        self.assertEqual(cmd, [
            "npx", "tsx", engine_main,
            "--workflow", "address-review",
            "--repo", str(Path("/ws")),
            "--pr", "7",
            "--round", "2",
            "--max-rounds", "3",
        ])

    def test_shft_afk_cmd_with_issue(self):
        shft_bin = str(Path("/df") / "shft" / "shft")
        cmd = self._capture_cmd(_dispatch_shft_afk, tracking_number=42)
        self.assertEqual(cmd, [shft_bin, "afk", "1", "--issue", "42"])

    def test_shft_afk_cmd_without_issue(self):
        shft_bin = str(Path("/df") / "shft" / "shft")
        cmd = self._capture_cmd(_dispatch_shft_afk, tracking_number=None)
        self.assertEqual(cmd, [shft_bin, "afk", "1"])


if __name__ == "__main__":
    unittest.main()
