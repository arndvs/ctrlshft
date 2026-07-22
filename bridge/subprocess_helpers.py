"""Shared subprocess lifecycle helpers for bridge modules."""

from __future__ import annotations

import logging
import os
import signal
import subprocess

DEFAULT_TERMINATE_GRACE_SECONDS = 3.5
DEFAULT_KILL_WAIT_SECONDS = 0.5


def terminate_process_group(
    proc: subprocess.Popen,
    *,
    grace_seconds: float = DEFAULT_TERMINATE_GRACE_SECONDS,
    kill_wait_seconds: float = DEFAULT_KILL_WAIT_SECONDS,
    logger: logging.Logger | None = None,
) -> None:
    """Terminate a child process group with SIGTERM, then SIGKILL if needed."""
    if proc.poll() is not None:
        return
    try:
        pgid = os.getpgid(proc.pid)
    except (ProcessLookupError, OSError):
        return
    try:
        os.killpg(pgid, signal.SIGTERM)
    except (ProcessLookupError, OSError):
        pass
    try:
        proc.wait(timeout=grace_seconds)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(pgid, signal.SIGKILL)
        except (ProcessLookupError, OSError):
            pass
        try:
            proc.wait(timeout=kill_wait_seconds)
        except subprocess.TimeoutExpired:
            if logger is not None:
                logger.warning("Process group %s did not exit after SIGKILL", pgid)
