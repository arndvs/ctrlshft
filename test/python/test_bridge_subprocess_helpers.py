"""Unit tests for shared bridge subprocess lifecycle helpers."""

from __future__ import annotations

import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT))

from bridge.subprocess_helpers import terminate_process_group


def _proc(pid: int = 4321, wait_side_effect=None, poll_return=None):
    proc = mock.MagicMock()
    proc.pid = pid
    proc.poll.return_value = poll_return
    if wait_side_effect is not None:
        proc.wait.side_effect = wait_side_effect
    else:
        proc.wait.return_value = 0
    return proc


class TestTerminateProcessGroup(unittest.TestCase):
    def test_normal_exited_process_is_noop(self):
        proc = _proc(poll_return=0)

        with mock.patch("bridge.subprocess_helpers.os.getpgid", create=True) as getpgid, \
                mock.patch("bridge.subprocess_helpers.os.killpg", create=True) as killpg:
            terminate_process_group(proc)

        getpgid.assert_not_called()
        killpg.assert_not_called()
        proc.wait.assert_not_called()

    def test_sigterm_sufficient_exit(self):
        proc = _proc(wait_side_effect=[0])

        with mock.patch("bridge.subprocess_helpers.os.getpgid", return_value=proc.pid, create=True), \
                mock.patch("bridge.subprocess_helpers.os.killpg", create=True) as killpg, \
                mock.patch("bridge.subprocess_helpers.signal.SIGTERM", 15, create=True):
            terminate_process_group(proc, grace_seconds=3.5, kill_wait_seconds=0.5)

        killpg.assert_called_once_with(4321, 15)
        proc.wait.assert_called_once_with(timeout=3.5)

    def test_sigkill_escalation(self):
        # Walk the escalation ladder in one scenario: SIGTERM then SIGKILL when the
        # SIGTERM wait times out, and a warning when even SIGKILL does not stop the
        # group. Asserting the exact call list catches double-SIGKILL or
        # SIGKILL-before-SIGTERM regressions that a bare count would miss.
        cases = [
            ("escalates to sigkill",
             [subprocess.TimeoutExpired("cmd", 3.5), 0],
             False),
            ("logs warning after sigkill timeout",
             [subprocess.TimeoutExpired("cmd", 3.5), subprocess.TimeoutExpired("cmd", 0.5)],
             True),
        ]
        for label, waits, expect_warning in cases:
            with self.subTest(label=label):
                proc = _proc(wait_side_effect=waits)
                logger = mock.MagicMock()

                with mock.patch("bridge.subprocess_helpers.os.getpgid", return_value=proc.pid, create=True), \
                        mock.patch("bridge.subprocess_helpers.os.killpg", create=True) as killpg, \
                        mock.patch("bridge.subprocess_helpers.signal.SIGTERM", 15, create=True), \
                        mock.patch("bridge.subprocess_helpers.signal.SIGKILL", 9, create=True):
                    terminate_process_group(proc, grace_seconds=3.5,
                                            kill_wait_seconds=0.5, logger=logger)

                self.assertEqual(killpg.call_args_list, [mock.call(4321, 15), mock.call(4321, 9)])
                proc.wait.assert_has_calls([
                    mock.call(timeout=3.5),
                    mock.call(timeout=0.5),
                ])
                if expect_warning:
                    logger.warning.assert_called_once_with(
                        "Process group %s did not exit after SIGKILL", 4321
                    )
                else:
                    logger.warning.assert_not_called()

    def test_already_missing_process_group_is_noop(self):
        proc = _proc()

        with mock.patch("bridge.subprocess_helpers.os.getpgid", side_effect=ProcessLookupError, create=True), \
                mock.patch("bridge.subprocess_helpers.os.killpg", create=True) as killpg:
            terminate_process_group(proc)

        killpg.assert_not_called()
        proc.wait.assert_not_called()


if __name__ == "__main__":
    unittest.main()
