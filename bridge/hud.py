"""HUD event emission.

Wraps ~/dotfiles/bin/write-hud-state.sh. Events are best-effort — if the
HUD daemon is down, emission fails silently and the worker continues.
"""
from __future__ import annotations

import json
import logging
import os
import queue
import subprocess
import threading
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

_SAFE_ENV_VARS = ("HOME", "PATH", "TERM", "LANG", "USER")
_EMIT_QUEUE_MAX = 128

_emit_queue: "queue.Queue[tuple[str, str, dict]]" = queue.Queue(maxsize=_EMIT_QUEUE_MAX)
_emit_worker_started = False
_emit_worker_lock = threading.Lock()


def _emit_worker() -> None:
    while True:
        hud_script, payload_json, safe_env = _emit_queue.get()
        try:
            _run_emit(hud_script, payload_json, safe_env)
        finally:
            _emit_queue.task_done()


def _ensure_emit_worker() -> None:
    global _emit_worker_started
    with _emit_worker_lock:
        if _emit_worker_started:
            return
        threading.Thread(target=_emit_worker, name="hud-emit-worker", daemon=True).start()
        _emit_worker_started = True


def _run_emit(hud_script: str, payload_json: str, safe_env: dict) -> None:
    try:
        subprocess.run(
            ["bash", hud_script, "bridge-event"],
            input=payload_json,
            text=True,
            check=False,
            timeout=2,
            env=safe_env,
        )
    except Exception as e:
        logger.debug("HUD emit failed (non-fatal): %s", e)


def _run_emit(hud_script: str, payload_json: str, safe_env: dict) -> None:
    try:
        subprocess.run(
            ["bash", hud_script, "bridge-event"],
            input=payload_json,
            text=True,
            check=False,
            timeout=2,
            env=safe_env,
        )
    except Exception as e:
        logger.debug("HUD emit failed (non-fatal): %s", e)


def emit(
    hud_script: Path,
    event: str,
    *,
    project: str,
    workspace_id: Optional[str] = None,
    worker_id: Optional[str] = None,
    delivery_id: Optional[str] = None,
    pr_number: Optional[int] = None,
    **extra,
) -> None:
    """Fire-and-forget HUD event.

    project is the GitHub repo full_name (the existing HUD per-project
    tab key). workspace_id and worker_id are Phase 2 forward-compat;
    HUD ignores them today, will use them later.
    """
    payload = {
        "type": event,
        "message": event,
        "project": project,
        **({"workspace_id": workspace_id} if workspace_id else {}),
        **({"worker_id": worker_id} if worker_id else {}),
        **({"delivery_id": delivery_id} if delivery_id else {}),
        **({"pr_number": pr_number} if pr_number else {}),
        **extra,
    }
    # Scrub environment — HUD emitter only needs basic shell vars,
    # not secrets from the worker's EnvironmentFile.
    safe_env = {k: os.environ[k] for k in _SAFE_ENV_VARS if k in os.environ}
    payload_json = json.dumps(payload)
    _ensure_emit_worker()
    try:
        _emit_queue.put_nowait((str(hud_script), payload_json, safe_env))
    except queue.Full:
        logger.debug("HUD emit queue full; dropping event (non-fatal)")
