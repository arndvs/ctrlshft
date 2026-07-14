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
import shutil
import signal
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT))

import bridge.worker as worker_module
from bridge.worker import (
    _build_subprocess_env,
    _dispatch_address_review,
    _dispatch_shft_afk,
    _process_job,
    _reap_orphaned_workspaces,
    _run_subprocess,
)
from bridge import db
from bridge.github import PrMetadata, Token, UnresolvedThread

_TOKEN = Token(value="ghs_test", expires_at="2026-01-01T00:00:00Z")


class TestShutdownSignal(unittest.TestCase):
    def setUp(self):
        worker_module._shutdown_event.clear()

    def tearDown(self):
        if hasattr(worker_module, "_shutdown_event"):
            worker_module._shutdown_event.clear()

    def test_install_shutdown_handlers_set_flag(self):
        with mock.patch("bridge.worker.signal.signal") as signal_fn:
            worker_module._install_shutdown_handlers()

        handlers = {call.args[0]: call.args[1] for call in signal_fn.call_args_list}
        self.assertIn(signal.SIGTERM, handlers)
        self.assertIn(signal.SIGINT, handlers)
        self.assertFalse(worker_module._shutdown_requested())

        handlers[signal.SIGTERM](signal.SIGTERM, None)

        self.assertTrue(worker_module._shutdown_requested())


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
    p.poll.return_value = None
    if wait_side_effect is not None:
        p.wait.side_effect = wait_side_effect
    else:
        p.wait.return_value = returncode
    return p


class TestRunSubprocess(unittest.TestCase):
    def setUp(self):
        worker_module._shutdown_event.clear()

    def tearDown(self):
        worker_module._shutdown_event.clear()

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
        proc = _proc(wait_side_effect=[0])
        with mock.patch("bridge.worker.time.monotonic", side_effect=[0, worker_module.SHFT_RUN_TIMEOUT_SECONDS + 1]):
            raised, killpg, emit = self._run(proc)
        self.assertIsInstance(raised, RuntimeError)
        killpg.assert_called_once_with(4321, 15)
        proc.wait.assert_called_once_with(timeout=worker_module.PROCESS_TERMINATE_GRACE_SECONDS)
        self.assertFalse(
            any(call.args[0] == "bridge.job.failed" for call in emit.call_args_list)
        )

    def test_shutdown_sigterm_kills_process_group(self):
        calls = {"count": 0}

        def wait_side_effect(timeout):
            calls["count"] += 1
            if calls["count"] == 1:
                worker_module._shutdown_event.set()
                raise subprocess.TimeoutExpired("cmd", timeout)
            return 0

        proc = _proc(wait_side_effect=wait_side_effect)

        raised, killpg, emit = self._run(proc)

        self.assertIsInstance(raised, RuntimeError)
        self.assertIn("worker_shutdown", str(raised))
        killpg.assert_called_once_with(4321, 15)
        proc.wait.assert_has_calls([
            mock.call(timeout=worker_module.SUBPROCESS_POLL_SECONDS),
            mock.call(timeout=worker_module.PROCESS_TERMINATE_GRACE_SECONDS),
        ])
        self.assertFalse(
            any(call.args[0] == "bridge.job.failed" for call in emit.call_args_list)
        )

    def test_shutdown_after_child_exit_keeps_successful_result(self):
        def wait_side_effect(timeout):
            worker_module._shutdown_event.set()
            raise subprocess.TimeoutExpired("cmd", timeout)

        proc = _proc(wait_side_effect=wait_side_effect)
        proc.poll.side_effect = [None, 0]

        raised, killpg, emit = self._run(proc)

        self.assertIsNone(raised)
        killpg.assert_not_called()
        emit.assert_any_call("bridge.job.shft_completed", exit_code=0)

    def test_timeout_escalates_to_sigkill(self):
        # Initial wait + the SIGTERM wait both time out → ordered escalation:
        # SIGTERM (15) then SIGKILL (9) on the same process group, no extra or
        # reordered calls. The exact call list catches double-SIGKILL or
        # SIGKILL-before-SIGTERM regressions that a bare count would miss.
        proc = _proc(wait_side_effect=[
            subprocess.TimeoutExpired("cmd", 1),
            subprocess.TimeoutExpired("cmd", 1),
        ])
        with mock.patch("bridge.worker.time.monotonic", side_effect=[0, worker_module.SHFT_RUN_TIMEOUT_SECONDS + 1]):
            raised, killpg, emit = self._run(proc)
        self.assertIsInstance(raised, RuntimeError)
        self.assertEqual(
            killpg.call_args_list, [mock.call(4321, 15), mock.call(4321, 9)]
        )
        proc.wait.assert_has_calls([
            mock.call(timeout=worker_module.PROCESS_TERMINATE_GRACE_SECONDS),
            mock.call(timeout=worker_module.PROCESS_KILL_WAIT_SECONDS),
        ])


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
        sandcastle_run = str(Path("/df") / ".sandcastle" / "run.ts")
        tsx_bin = str(Path("/df") / ".sandcastle" / "engine" / "node_modules" / ".bin" / "tsx")
        cmd = self._capture_cmd(
            _dispatch_address_review, pr_number=7, iteration_num=2, max_iterations=3
        )
        self.assertEqual(cmd, [
            tsx_bin, sandcastle_run,
            "address-review",
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


class TestReapOrphanedWorkspaces(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.db_path = self.root / "state.db"
        self.workspaces_root = self.root / "workspaces"
        db.init_db(self.db_path)

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def _cfg(self):
        cfg = mock.MagicMock()
        cfg.db_path = self.db_path
        cfg.workspaces_root = self.workspaces_root
        return cfg

    def test_reaper_deletes_inactive_workspace_with_separator_in_name(self):
        inactive = self.workspaces_root / "org--name--repo--name--pr7"
        inactive.mkdir(parents=True)

        _reap_orphaned_workspaces(self._cfg())

        self.assertFalse(inactive.exists())

    def test_reaper_preserves_active_workspace(self):
        active = self.workspaces_root / "org--repo--pr7"
        active.mkdir(parents=True)
        with db.connect(self.db_path) as conn:
            db.enqueue(
                conn,
                delivery_id="d1",
                event_type="pull_request_review",
                repo_full_name="org/repo",
                pr_number=7,
                payload={},
            )

        _reap_orphaned_workspaces(self._cfg())

        self.assertTrue(active.exists())

    def test_reaper_skips_symlinks(self):
        target = self.root / "outside"
        target.mkdir()
        link = self.workspaces_root / "org--repo--pr7"
        self.workspaces_root.mkdir()
        try:
            link.symlink_to(target, target_is_directory=True)
        except OSError:
            child = mock.MagicMock()
            child.is_dir.return_value = True
            child.is_symlink.return_value = True
            root = mock.MagicMock()
            root.exists.return_value = True
            root.iterdir.return_value = [child]
            cfg = self._cfg()
            cfg.workspaces_root = root
            with mock.patch("bridge.worker.shutil.rmtree") as rmtree:
                _reap_orphaned_workspaces(cfg)
            rmtree.assert_not_called()
            return

        _reap_orphaned_workspaces(self._cfg())

        self.assertTrue(link.exists())
        self.assertTrue(target.exists())

    def test_reaper_logs_and_returns_when_workspace_root_listing_fails(self):
        root = mock.MagicMock()
        root.exists.return_value = True
        root.iterdir.side_effect = OSError("permission denied")
        cfg = self._cfg()
        cfg.workspaces_root = root

        with mock.patch("bridge.worker.logger.warning") as warning:
            _reap_orphaned_workspaces(cfg)

        warning.assert_called_once_with(
            "Failed to list workspace root for reaping: %s", root, exc_info=True
        )


class TestProcessJob(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.db_path = self.root / "state.db"
        db.init_db(self.db_path)

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def _cfg(self):
        cfg = mock.MagicMock()
        cfg.db_path = self.db_path
        cfg.hud_script = Path("/hud")
        cfg.mint_script = Path("/mint")
        cfg.max_iterations = 3
        cfg.copilot_bot_login = "copilot-pull-request-reviewer[bot]"
        cfg.workspaces_root = self.root / "workspaces"
        return cfg

    def _claimed_job(self):
        with db.connect(self.db_path) as conn:
            db.enqueue(
                conn,
                delivery_id="d1",
                event_type="pull_request_review",
                repo_full_name="org/repo",
                pr_number=7,
                payload={"review": {"html_url": "https://example.test/review"}},
            )
            return db.claim_next_job(conn, "worker-1")

    def test_dispatch_failure_does_not_bump_iteration(self):
        cfg = self._cfg()
        job = self._claimed_job()
        thread = UnresolvedThread(
            thread_id="thread-1",
            url="https://example.test/thread",
            path="bridge/worker.py",
            line=1,
            body="fix this",
            diff_hunk=None,
            author="copilot-pull-request-reviewer[bot]",
        )

        with mock.patch("bridge.worker.hud.emit"), \
                mock.patch("bridge.worker.github.mint_token", return_value=_TOKEN), \
                mock.patch("bridge.worker.github.fetch_unresolved_copilot_threads", return_value=[thread]), \
                mock.patch("bridge.worker.github.find_tracking_issue", return_value=None), \
                mock.patch(
                    "bridge.worker.github.fetch_pr_metadata",
                    return_value=PrMetadata(
                        head_ref="feature",
                        head_repo_full_name="org/repo",
                        title="Test PR",
                        html_url="https://example.test/pr/7",
                    ),
                ), \
                mock.patch("bridge.worker.workspace.prepare", return_value=self.root / "workspaces" / "org--repo--pr7"), \
                mock.patch("bridge.worker.github.create_issue", return_value=42), \
                mock.patch("bridge.worker._dispatch_address_review", side_effect=RuntimeError("dispatch failed")):
            with self.assertRaises(RuntimeError):
                _process_job(cfg, job, "worker-1")

        with db.connect(self.db_path) as conn:
            self.assertEqual(db.read_iteration(conn, "org/repo#7"), 0)

    def test_iteration_event_matches_dispatched_round(self):
        cfg = self._cfg()
        job = self._claimed_job()
        thread = UnresolvedThread(
            thread_id="thread-1",
            url="https://example.test/thread",
            path="bridge/worker.py",
            line=1,
            body="fix this",
            diff_hunk=None,
            author="copilot-pull-request-reviewer[bot]",
        )
        emit_calls = []

        def capture_emit(_hud_script, event, **extra):
            emit_calls.append((event, extra))

        with mock.patch("bridge.worker.hud.emit", side_effect=capture_emit), \
                mock.patch("bridge.worker.github.mint_token", return_value=_TOKEN), \
                mock.patch("bridge.worker.github.fetch_unresolved_copilot_threads", return_value=[thread]), \
                mock.patch("bridge.worker.github.find_tracking_issue", return_value=None), \
                mock.patch(
                    "bridge.worker.github.fetch_pr_metadata",
                    return_value=PrMetadata(
                        head_ref="feature",
                        head_repo_full_name="org/repo",
                        title="Test PR",
                        html_url="https://example.test/pr/7",
                    ),
                ), \
                mock.patch("bridge.worker.workspace.prepare", return_value=self.root / "workspaces" / "org--repo--pr7"), \
                mock.patch("bridge.worker.github.create_issue", return_value=42), \
                mock.patch("bridge.worker._run_subprocess"):
            _process_job(cfg, job, "worker-1")

        iteration_event = next(
            extra for event, extra in emit_calls if event == "bridge.job.iteration"
        )
        address_review_event = next(
            extra for event, extra in emit_calls if event == "bridge.job.address_review"
        )
        self.assertEqual(iteration_event["iteration"], address_review_event["round"])

    def test_iteration_event_not_emitted_when_cap_exceeded(self):
        cfg = self._cfg()
        job = self._claimed_job()
        thread = UnresolvedThread(
            thread_id="thread-1",
            url="https://example.test/thread",
            path="bridge/worker.py",
            line=1,
            body="fix this",
            diff_hunk=None,
            author="copilot-pull-request-reviewer[bot]",
        )
        emit_calls = []

        with db.connect(self.db_path) as conn:
            for _ in range(cfg.max_iterations):
                db.bump_iteration(conn, "org/repo#7")

        def capture_emit(_hud_script, event, **extra):
            emit_calls.append((event, extra))

        with mock.patch("bridge.worker.hud.emit", side_effect=capture_emit), \
                mock.patch("bridge.worker.github.mint_token", return_value=_TOKEN), \
                mock.patch("bridge.worker.github.fetch_unresolved_copilot_threads", return_value=[thread]), \
                mock.patch("bridge.worker.github.find_tracking_issue", return_value=None), \
                mock.patch("bridge.worker._dispatch_address_review") as dispatch:
            _process_job(cfg, job, "worker-1")

        event_names = [event for event, _extra in emit_calls]
        self.assertNotIn("bridge.job.iteration", event_names)
        self.assertIn("bridge.loop.cap_exceeded", event_names)
        dispatch.assert_not_called()

    def test_process_one_job_marks_shutdown_failure_with_clear_error(self):
        cfg = self._cfg()
        with db.connect(self.db_path) as conn:
            db.enqueue(
                conn,
                delivery_id="d1",
                event_type="pull_request_review",
                repo_full_name="org/repo",
                pr_number=7,
                payload={},
            )

        with mock.patch("bridge.worker._process_job", side_effect=worker_module.WorkerShutdown("worker_shutdown")), \
                mock.patch("bridge.worker._cleanup_workspace_after_job") as cleanup, \
                mock.patch("bridge.worker.hud.emit") as emit:
            processed = worker_module.process_one_job(cfg, "worker-1")

        self.assertTrue(processed)
        cleanup.assert_called_once()
        emit.assert_any_call(
            cfg.hud_script,
            "bridge.job.failed",
            project="org/repo",
            workspace_id="org/repo#7",
            worker_id="worker-1",
            delivery_id="d1",
            pr_number=7,
            error="worker_shutdown",
        )
        with db.connect(self.db_path) as conn:
            row = conn.execute("SELECT status, error FROM jobs").fetchone()
        self.assertEqual(row["status"], "failed")
        self.assertEqual(row["error"], "worker_shutdown")

    def test_shutdown_failure_cleans_existing_workspace(self):
        cfg = self._cfg()
        with db.connect(self.db_path) as conn:
            db.enqueue(
                conn,
                delivery_id="d1",
                event_type="pull_request_review",
                repo_full_name="org/repo",
                pr_number=7,
                payload={},
            )

        workspace_path = cfg.workspaces_root / "org--repo--pr7"
        workspace_path.mkdir(parents=True)

        with mock.patch("bridge.worker._process_job", side_effect=worker_module.WorkerShutdown("worker_shutdown")), \
                mock.patch("bridge.worker.hud.emit") as emit:
            processed = worker_module.process_one_job(cfg, "worker-1")

        self.assertTrue(processed)
        self.assertFalse(workspace_path.exists())
        emit.assert_any_call(
            cfg.hud_script,
            "bridge.workspace.cleaned",
            project="org/repo",
            workspace_id="org/repo#7",
            worker_id="worker-1",
        )

    def test_run_cleans_once_after_processed_job(self):
        cfg = self._cfg()
        job = self._claimed_job()

        with mock.patch("bridge.worker.Config.from_env", return_value=cfg), \
                mock.patch.object(cfg, "require_github_app"), \
                mock.patch.object(cfg, "ensure_dirs"), \
                mock.patch("bridge.worker.db.init_db"), \
                mock.patch("bridge.worker.db.requeue_stale_claims", return_value=0), \
                mock.patch("bridge.worker.db.claim_next_job", side_effect=[job, None]), \
                mock.patch("bridge.worker._process_job"), \
                mock.patch("bridge.worker.db.mark_done"), \
                mock.patch("bridge.worker._cleanup_workspace_after_job") as cleanup, \
                mock.patch.object(
                    worker_module._shutdown_event,
                    "wait",
                    side_effect=lambda _seconds: worker_module._shutdown_event.set() or True,
                ):
            worker_module.run("worker-1")

        cleanup.assert_called_once_with(cfg, job, "worker-1")

    def test_run_does_not_cleanup_or_emit_cleaned_when_no_job_claimed(self):
        cfg = self._cfg()

        with mock.patch("bridge.worker.Config.from_env", return_value=cfg), \
                mock.patch.object(cfg, "require_github_app"), \
                mock.patch.object(cfg, "ensure_dirs"), \
                mock.patch("bridge.worker.db.init_db"), \
                mock.patch("bridge.worker.db.requeue_stale_claims", return_value=0), \
                mock.patch("bridge.worker.db.claim_next_job", return_value=None), \
                mock.patch("bridge.worker._cleanup_workspace_after_job") as cleanup, \
                mock.patch("bridge.worker.hud.emit") as emit, \
                mock.patch.object(
                    worker_module._shutdown_event,
                    "wait",
                    side_effect=lambda _seconds: worker_module._shutdown_event.set() or True,
                ):
            worker_module.run("worker-1")

        cleanup.assert_not_called()
        self.assertFalse(
            any(call.args[1] == "bridge.workspace.cleaned" for call in emit.call_args_list)
        )

    def test_run_exits_idle_loop_when_shutdown_requested(self):
        cfg = self._cfg()

        def request_shutdown(_seconds):
            worker_module._shutdown_event.set()
            return True

        with mock.patch("bridge.worker.Config.from_env", return_value=cfg), \
                mock.patch.object(cfg, "require_github_app"), \
                mock.patch.object(cfg, "ensure_dirs"), \
                mock.patch("bridge.worker.db.init_db"), \
                mock.patch("bridge.worker.db.requeue_stale_claims", return_value=0), \
                mock.patch("bridge.worker.db.claim_next_job", return_value=None) as claim, \
                mock.patch("bridge.worker._install_shutdown_handlers") as install, \
                mock.patch.object(worker_module._shutdown_event, "wait", side_effect=request_shutdown) as wait:
            worker_module.run("worker-1")

        install.assert_called_once()
        claim.assert_called_once()
        wait.assert_called_once_with(worker_module.POLL_INTERVAL_SECONDS)

    def test_run_emits_worker_shutdown_event(self):
        cfg = self._cfg()

        with mock.patch("bridge.worker.Config.from_env", return_value=cfg), \
                mock.patch.object(cfg, "require_github_app"), \
                mock.patch.object(cfg, "ensure_dirs"), \
                mock.patch("bridge.worker.db.init_db"), \
                mock.patch("bridge.worker.db.requeue_stale_claims", return_value=0), \
                mock.patch("bridge.worker.db.claim_next_job", return_value=None), \
                mock.patch("bridge.worker.hud.emit") as emit, \
                mock.patch.object(
                    worker_module._shutdown_event,
                    "wait",
                    side_effect=lambda _seconds: worker_module._shutdown_event.set() or True,
                ):
            worker_module.run("worker-1")

        emit.assert_any_call(
            cfg.hud_script,
            "bridge.worker.shutdown",
            project="bridge-worker",
            worker_id="worker-1",
            reason="shutdown_requested",
        )


class TestCleanupWorkspaceAfterJob(unittest.TestCase):
    def test_missing_workspace_does_not_emit_cleaned_event(self):
        cfg = mock.MagicMock()
        cfg.hud_script = Path("/hud")
        cfg.workspaces_root = Path("/workspaces")
        job = mock.MagicMock()
        job.repo_full_name = "org/repo"
        job.claim_key = "org/repo#7"
        workspace_path = mock.MagicMock()
        workspace_path.exists.return_value = False

        with mock.patch("bridge.worker.workspace.cleanup") as cleanup, \
                mock.patch("bridge.worker.workspace.workspace_path", return_value=workspace_path), \
                mock.patch("bridge.worker.hud.emit") as emit:
            worker_module._cleanup_workspace_after_job(cfg, job, "worker-1")

        cleanup.assert_called_once_with(Path("/workspaces"), "org/repo#7")
        emit.assert_not_called()

    def test_hud_emit_failure_does_not_report_cleanup_failure(self):
        cfg = mock.MagicMock()
        cfg.hud_script = Path("/hud")
        cfg.workspaces_root = Path("/workspaces")
        job = mock.MagicMock()
        job.repo_full_name = "org/repo"
        job.claim_key = "org/repo#7"
        workspace_path = mock.MagicMock()
        workspace_path.exists.return_value = True

        with mock.patch("bridge.worker.workspace.cleanup") as cleanup, \
                mock.patch("bridge.worker.workspace.workspace_path", return_value=workspace_path), \
                mock.patch("bridge.worker.hud.emit", side_effect=RuntimeError("hud failed")), \
                mock.patch("bridge.worker.logger.warning") as warning:
            worker_module._cleanup_workspace_after_job(cfg, job, "worker-1")

        cleanup.assert_called_once_with(Path("/workspaces"), "org/repo#7")
        warning.assert_called_once()
        self.assertIn("HUD cleanup event failed", warning.call_args.args[0])


if __name__ == "__main__":
    unittest.main()
