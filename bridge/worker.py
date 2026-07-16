"""Bridge worker — the persistent process.

Polls the SQLite queue, claims jobs, processes them, execs shft afk 1
as a subprocess. systemd template unit invokes this with WORKER_ID set
to the instance number.

MVP constraints (documented, accepted):
- Global lockfile at /tmp/shft-afk.lock limits to single concurrent
  shft invocation across all bridge + manual runs.
- Global ~/dotfiles/working/ means HUD events don't distinguish bridge
  vs manual sessions. Phase 2 follows ADR-NNNN for per-workspace isolation.
"""
from __future__ import annotations

import logging
import os
import shutil
import signal
import subprocess
import sys
import threading
import time
import traceback

import httpx

from . import db, github, hud, issue, workspace
from .config import Config
from .git_creds import git_credential_env

logger = logging.getLogger("bridge.worker")

POLL_INTERVAL_SECONDS = 2.0
SHFT_RUN_TIMEOUT_SECONDS = 60 * 30  # 30 min hard cap per shft invocation
SUBPROCESS_POLL_SECONDS = 0.5
PROCESS_TERMINATE_GRACE_SECONDS = 3.5
PROCESS_KILL_WAIT_SECONDS = 0.5
_shutdown_event = threading.Event()
_shutdown_signum: int | None = None


def _request_shutdown(signum, _frame) -> None:
    global _shutdown_signum
    _shutdown_signum = signum
    _shutdown_event.set()


def _install_shutdown_handlers() -> None:
    signal.signal(signal.SIGTERM, _request_shutdown)
    signal.signal(signal.SIGINT, _request_shutdown)


def _shutdown_requested() -> bool:
    return _shutdown_event.is_set()


class WorkerShutdown(RuntimeError):
    """Raised when a worker shutdown interrupts active subprocess work."""


def _process_job(cfg: Config, job: db.Job, worker_id: str) -> None:
    repo = job.repo_full_name
    owner, repo_name = repo.split("/", 1)
    workspace_id = job.claim_key

    def emit(event: str, **extra) -> None:
        hud.emit(
            cfg.hud_script,
            event,
            project=repo,
            workspace_id=workspace_id,
            worker_id=worker_id,
            delivery_id=job.delivery_id,
            pr_number=job.pr_number,
            **extra,
        )

    emit("bridge.job.claimed")

    # 1. Mint token.
    try:
        token = github.mint_token(cfg.mint_script, shutdown_check=_shutdown_requested)
    except github.GitHubError:
        if _shutdown_requested():
            raise WorkerShutdown("worker_shutdown")
        raise
    if _shutdown_requested():
        raise WorkerShutdown("worker_shutdown")
    emit("bridge.job.token_minted", expires_at=token.expires_at)

    # 2. Fetch unresolved threads.
    threads = github.fetch_unresolved_copilot_threads(
        token,
        owner=owner,
        repo=repo_name,
        pr_number=job.pr_number,
        copilot_login=cfg.copilot_bot_login,
    )
    emit("bridge.job.threads_found", count=len(threads))

    marker_str = issue.marker(repo, job.pr_number)
    existing = github.find_tracking_issue(
        token, owner=owner, repo=repo_name, marker=marker_str
    )

    # 3. Decide and act.
    if not threads and existing:
        github.update_issue(
            token,
            owner=owner,
            repo=repo_name,
            issue_number=existing["number"],
            state="closed",
        )
        github.comment_on_issue(
            token,
            owner=owner,
            repo=repo_name,
            issue_number=existing["number"],
            body="All Copilot review threads resolved. Closing.",
        )
        emit(
            "bridge.job.issue_closed",
            tracking_issue_number=existing["number"],
        )
        # Persist tracking-issue number so mark_done records it (CC-review)
        with db.connect(cfg.db_path) as conn:
            conn.execute(
                "UPDATE jobs SET tracking_issue_number=? WHERE id=?",
                (existing["number"], job.id),
            )
        return

    if not threads:
        emit("bridge.job.done", reason="no_threads_no_issue")
        return

    # Iteration cap check (read-only — fixes iteration-burn-on-failure).
    with db.connect(cfg.db_path) as conn:
        current_iteration = db.read_iteration(conn, job.claim_key)
    next_iteration = current_iteration + 1

    if current_iteration >= cfg.max_iterations:
        emit("bridge.loop.cap_exceeded", iteration=current_iteration)
        if existing:
            try:
                github.add_label(
                    token,
                    owner=owner,
                    repo=repo_name,
                    issue_number=existing["number"],
                    label="agent-loop-exceeded",
                )
            except Exception:
                logger.warning("Failed to add agent-loop-exceeded label (may not exist)")
            github.comment_on_issue(
                token,
                owner=owner,
                repo=repo_name,
                issue_number=existing["number"],
                body=(
                    f"Iteration cap ({cfg.max_iterations}) exceeded. "
                    "Stopping autonomous loop. Human review required."
                ),
            )
        return

    emit("bridge.job.iteration", iteration=next_iteration)

    # 4. Prepare workspace — fetch PR metadata via REST helper (fixes H-3).
    pr_meta = github.fetch_pr_metadata(
        token, owner=owner, repo=repo_name, pr_number=job.pr_number
    )
    review_event_url = job.payload.get("review", {}).get("html_url", "")

    try:
        ws_path = workspace.prepare(
            cfg.workspaces_root,
            token=token,
            repo_full_name=repo,
            pr_number=job.pr_number,
            head_ref=pr_meta.head_ref,
            head_repo_full_name=pr_meta.head_repo_full_name,
            shutdown_check=_shutdown_requested,
        )
    except workspace.WorkspaceError:
        if _shutdown_requested():
            raise WorkerShutdown("worker_shutdown")
        raise
    if _shutdown_requested():
        raise WorkerShutdown("worker_shutdown")
    emit("bridge.workspace.prepared", path=str(ws_path))

    # 5. Upsert tracking issue.
    title_str = issue.title(job.pr_number, pr_meta.title)
    body_str = issue.body(
        repo_full_name=repo,
        pr_number=job.pr_number,
        pr_url=pr_meta.html_url,
        branch=pr_meta.head_ref,
        review_event_url=review_event_url,
        threads=threads,
    )

    if existing:
        github.update_issue(
            token,
            owner=owner,
            repo=repo_name,
            issue_number=existing["number"],
            body=body_str,
        )
        tracking_number = existing["number"]
        emit("bridge.job.issue_updated", tracking_issue_number=tracking_number)
    else:
        try:
            tracking_number = github.create_issue(
                token,
                owner=owner,
                repo=repo_name,
                title=title_str,
                body=body_str,
                labels=issue.ISSUE_LABELS,
            )
        except httpx.HTTPStatusError as e:
            if e.response.status_code != 422:
                raise
            # Only retry without labels if the 422 is specifically about invalid labels
            try:
                err_data = e.response.json()
                errors = err_data.get("errors", [])
                is_label_error = any(
                    err.get("resource") == "Label"
                    or "label" in str(err.get("message", "")).lower()
                    for err in errors
                )
            except Exception:
                is_label_error = False
            if not is_label_error:
                raise
            logger.warning("create_issue with labels failed (422, label validation); retrying without labels")
            tracking_number = github.create_issue(
                token,
                owner=owner,
                repo=repo_name,
                title=title_str,
                body=body_str,
                labels=[],
            )
        emit("bridge.job.issue_created", tracking_issue_number=tracking_number)

    with db.connect(cfg.db_path) as conn:
        conn.execute(
            "UPDATE jobs SET tracking_issue_number=?, workspace_path=? WHERE id=?",
            (tracking_number, str(ws_path), job.id),
        )

    # 6. Dispatch to the appropriate workflow.
    env = _build_subprocess_env(cfg, token, ws_path, repo)

    emit("bridge.job.shft_invoked")

    if job.event_type == "pull_request_review":
        # Copilot review event — use the typed address-review workflow
        _dispatch_address_review(
            cfg=cfg,
            ws_path=ws_path,
            env=env,
            pr_number=job.pr_number,
            iteration_num=next_iteration,
            max_iterations=cfg.max_iterations,
            emit=emit,
        )
    else:
        # Generic issue/PR event — use shft afk
        _dispatch_shft_afk(
            cfg=cfg,
            ws_path=ws_path,
            env=env,
            tracking_number=tracking_number,
            emit=emit,
        )

    # Bump iteration AFTER successful dispatch (fixes iteration-burn-on-failure).
    with db.connect(cfg.db_path) as conn:
        iteration_num = db.bump_iteration(conn, job.claim_key)
        conn.execute(
            "UPDATE jobs SET iteration = ? WHERE id = ?",
            (iteration_num, job.id),
        )


def _build_subprocess_env(cfg: Config, token, ws_path, repo: str) -> dict[str, str]:
    """Build a scrubbed environment for subprocess execution."""
    existing_path = os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin")
    local_bin = os.path.expanduser("~/.local/bin")
    if local_bin not in existing_path.split(":"):
        path_val = f"{local_bin}:{existing_path}"
    else:
        path_val = existing_path
    env = {
        **git_credential_env(token),
        "HOME": os.environ.get("HOME", ""),
        "PATH": path_val,
        "TERM": os.environ.get("TERM", "dumb"),
        "LANG": os.environ.get("LANG", "en_US.UTF-8"),
        "USER": os.environ.get("USER", ""),
        "BRIDGE_WORKSPACE": str(ws_path),
        "GH_TOKEN": token.value,
        "GH_REPO": repo,
    }
    return env


def _terminate_process_group(proc) -> None:
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
        proc.wait(timeout=PROCESS_TERMINATE_GRACE_SECONDS)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(pgid, signal.SIGKILL)
        except (ProcessLookupError, OSError):
            pass
        try:
            proc.wait(timeout=PROCESS_KILL_WAIT_SECONDS)
        except subprocess.TimeoutExpired:
            logger.warning("Process group %s did not exit after SIGKILL", pgid)
            pass


def _wait_for_subprocess(proc, cmd: list[str]) -> None:
    deadline = time.monotonic() + SHFT_RUN_TIMEOUT_SECONDS
    while True:
        if proc.poll() is not None:
            return
        if _shutdown_requested():
            raise WorkerShutdown("worker_shutdown")
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise subprocess.TimeoutExpired(cmd, SHFT_RUN_TIMEOUT_SECONDS)
        try:
            proc.wait(timeout=min(SUBPROCESS_POLL_SECONDS, remaining))
            return
        except subprocess.TimeoutExpired:
            continue


def _run_subprocess(cmd: list[str], cwd: str, env: dict[str, str], emit) -> None:
    """Run a subprocess with timeout and process group cleanup."""
    proc = subprocess.Popen(
        cmd,
        cwd=cwd,
        env=env,
        start_new_session=True,
    )
    try:
        _wait_for_subprocess(proc, cmd)
        emit("bridge.job.shft_completed", exit_code=proc.returncode)
        if proc.returncode != 0:
            raise RuntimeError(f"{cmd[0]} exited {proc.returncode}")
    except WorkerShutdown:
        _terminate_process_group(proc)
        raise
    except subprocess.TimeoutExpired:
        _terminate_process_group(proc)
        raise RuntimeError(f"{cmd[0]} timed out")


def _dispatch_address_review(cfg: Config, ws_path, env: dict[str, str], pr_number: int, iteration_num: int, max_iterations: int, emit) -> None:
    """Dispatch to the engine's address-review workflow."""
    sandcastle_run = str(cfg.dotfiles_root / ".sandcastle" / "run.ts")
    tsx_bin = str(cfg.dotfiles_root / ".sandcastle" / "engine" / "node_modules" / ".bin" / "tsx")
    cmd = [
        tsx_bin, sandcastle_run,
        "address-review",
        "--repo", str(ws_path),
        "--pr", str(pr_number),
        "--round", str(iteration_num),
        "--max-rounds", str(max_iterations),
    ]
    emit("bridge.job.address_review", round=iteration_num)
    _run_subprocess(cmd, cwd=str(ws_path), env=env, emit=emit)


def _dispatch_shft_afk(cfg: Config, ws_path, env: dict[str, str], tracking_number: int | None, emit) -> None:
    """Dispatch to shft afk for generic issue/PR events."""
    shft_bin = str(cfg.dotfiles_root / "shft" / "shft")
    cmd = [shft_bin, "afk", "1"]
    if tracking_number:
        cmd += ["--issue", str(tracking_number)]
    _run_subprocess(cmd, cwd=str(ws_path), env=env, emit=emit)


def _reap_orphaned_workspaces(cfg: Config) -> None:
    """Remove workspace directories with no queued/claimed jobs.

    Called once at startup to reclaim disk from a previous crash.
    """
    root = cfg.workspaces_root
    if not root.exists():
        return

    with db.connect(cfg.db_path) as conn:
        active_keys = {
            row[0]
            for row in conn.execute(
                "SELECT DISTINCT claim_key FROM jobs WHERE status IN ('queued', 'claimed')"
            ).fetchall()
        }

    active_paths = {workspace.workspace_path(root, claim_key) for claim_key in active_keys}
    try:
        for child in root.iterdir():
            if child.is_symlink():
                continue
            if not child.is_dir():
                continue
            if child not in active_paths:
                try:
                    shutil.rmtree(child)
                    logger.info("Reaped orphaned workspace: %s", child)
                except Exception:
                    logger.warning("Failed to reap workspace: %s", child, exc_info=True)
    except OSError:
        logger.warning("Failed to list workspace root for reaping: %s", root, exc_info=True)


def _cleanup_workspace_after_job(cfg: Config, job: db.Job, worker_id: str) -> None:
    workspace_path = workspace.workspace_path(cfg.workspaces_root, job.claim_key)
    existed = workspace_path.exists()
    workspace.cleanup(cfg.workspaces_root, job.claim_key)
    if existed:
        try:
            hud.emit(
                cfg.hud_script,
                "bridge.workspace.cleaned",
                project=job.repo_full_name,
                workspace_id=job.claim_key,
                worker_id=worker_id,
            )
        except Exception:
            logger.warning("HUD cleanup event failed for %s", job.claim_key, exc_info=True)


def _emit_worker_shutdown(cfg: Config, worker_id: str) -> None:
    try:
        hud.emit(
            cfg.hud_script,
            "bridge.worker.shutdown",
            project="bridge-worker",
            worker_id=worker_id,
            reason="shutdown_requested",
        )
    except Exception:
        logger.warning("HUD worker shutdown event failed for %s", worker_id, exc_info=True)


def process_one_job(cfg: Config, worker_id: str) -> bool:
    """Claim and process one queued job.

    Returns True when a job was claimed, even if processing records it as failed.
    Returns False when the queue is empty.
    """
    with db.connect(cfg.db_path) as conn:
        job = db.claim_next_job(conn, worker_id)

    if job is None:
        return False

    try:
        _process_job(cfg, job, worker_id)
        with db.connect(cfg.db_path) as conn:
            db.mark_done(conn, job.id)
    except WorkerShutdown:
        logger.info("Job %s interrupted by worker shutdown", job.id)
        with db.connect(cfg.db_path) as conn:
            db.mark_failed(conn, job.id, "worker_shutdown")
        try:
            hud.emit(
                cfg.hud_script,
                "bridge.job.failed",
                project=job.repo_full_name,
                workspace_id=job.claim_key,
                worker_id=worker_id,
                delivery_id=job.delivery_id,
                pr_number=job.pr_number,
                error="worker_shutdown",
            )
        except Exception:
            logger.warning("HUD failure event failed for %s", job.claim_key, exc_info=True)
    except Exception as e:
        tb = traceback.format_exc()
        logger.error("Job %s failed: %s\n%s", job.id, e, tb)
        with db.connect(cfg.db_path) as conn:
            db.mark_failed(conn, job.id, tb)
        try:
            hud.emit(
                cfg.hud_script,
                "bridge.job.failed",
                project=job.repo_full_name,
                workspace_id=job.claim_key,
                worker_id=worker_id,
                delivery_id=job.delivery_id,
                pr_number=job.pr_number,
                error=str(e),
            )
        except Exception:
            logger.warning("HUD failure event failed for %s", job.claim_key, exc_info=True)
    finally:
        # Workspace cleanup — prevents unbounded disk growth.
        try:
            _cleanup_workspace_after_job(cfg, job, worker_id)
        except Exception:
            logger.warning("Workspace cleanup failed for %s", job.claim_key, exc_info=True)

    return True


def run(worker_id: str) -> None:
    global _shutdown_signum
    _shutdown_signum = None
    _shutdown_event.clear()
    _install_shutdown_handlers()
    cfg = Config.from_env()
    cfg.require_github_app()  # Worker needs GitHub App credentials — fail fast
    cfg.ensure_dirs()
    db.init_db(cfg.db_path)

    # On startup, requeue any jobs left in 'claimed' state from a previous
    # crash (lease expired — prevents permanently stuck jobs).
    with db.connect(cfg.db_path) as conn:
        requeued = db.requeue_stale_claims(conn)
        if requeued:
            logger.info("Requeued %d stale claimed job(s)", requeued)

    # Startup reaper: clean orphaned workspaces from previous runs.
    _reap_orphaned_workspaces(cfg)

    logger.info(
        "Worker %s started, polling every %.1fs",
        worker_id,
        POLL_INTERVAL_SECONDS,
    )

    while not _shutdown_requested():
        try:
            processed = process_one_job(cfg, worker_id)
        except Exception as e:
            logger.exception("Claim failed: %s", e)
            _shutdown_event.wait(POLL_INTERVAL_SECONDS)
            continue

        if not processed:
            _shutdown_event.wait(POLL_INTERVAL_SECONDS)

    logger.info("Worker %s shutdown complete (signal=%s)", worker_id, _shutdown_signum)
    _emit_worker_shutdown(cfg, worker_id)


if __name__ == "__main__":
    worker_id = (
        os.environ.get("WORKER_ID")
        or (sys.argv[1] if len(sys.argv) > 1 else "1")
    )
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(name)s %(levelname)s %(message)s",
    )
    run(worker_id)
