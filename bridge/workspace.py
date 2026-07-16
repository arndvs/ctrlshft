"""Per-PR workspace lifecycle.

A workspace is ~/bridge/workspaces/<owner>--<repo>--pr<num>/, a
single-branch clone of the PR's head. Reused across iterations for the
same PR; recreated if missing.

Security: Git credentials are injected via ephemeral GIT_CONFIG_COUNT
env vars (fixes S-1 from audit — no token ever touches .git/config).
"""
from __future__ import annotations

import logging
import os
import signal
import shutil
import subprocess
import tempfile
import time as _time
from pathlib import Path
from typing import Callable

from .git_creds import git_credential_env
from .github import Token

logger = logging.getLogger(__name__)

_SAFE_ENV_VARS = ("HOME", "PATH", "TERM", "LANG", "USER")
_GIT_POLL_SECONDS = 0.5


def _terminate_popen(proc: subprocess.Popen) -> None:
    """Terminate a Popen process group gracefully."""
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
        proc.wait(timeout=3.5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(pgid, signal.SIGKILL)
        except (ProcessLookupError, OSError):
            pass
        try:
            proc.wait(timeout=0.5)
        except subprocess.TimeoutExpired:
            pass


def _run_git(
    cmd: list[str],
    *,
    env: dict[str, str],
    timeout: float,
    shutdown_check: Callable[[], bool] | None = None,
) -> subprocess.CompletedProcess:
    """Run a git command with optional shutdown awareness.

    When shutdown_check is None, falls back to blocking subprocess.run.
    When provided, polls the subprocess and raises WorkspaceError on shutdown.
    """
    if shutdown_check is None:
        return subprocess.run(
            cmd,
            check=True,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
        )

    with tempfile.TemporaryFile(mode="w+", encoding="utf-8") as stdout_file, \
            tempfile.TemporaryFile(mode="w+", encoding="utf-8") as stderr_file:
        proc = subprocess.Popen(
            cmd,
            stdout=stdout_file,
            stderr=stderr_file,
            text=True,
            env=env,
            start_new_session=True,
        )
        deadline = _time.monotonic() + timeout
        try:
            while True:
                if shutdown_check():
                    _terminate_popen(proc)
                    raise WorkspaceError(
                        f"git operation interrupted by shutdown: {' '.join(cmd[:3])}"
                    )
                remaining = deadline - _time.monotonic()
                if remaining <= 0:
                    _terminate_popen(proc)
                    raise WorkspaceError(
                        f"git operation timed out after {timeout}s: {' '.join(cmd[:3])}"
                    )
                try:
                    proc.wait(timeout=min(_GIT_POLL_SECONDS, remaining))
                    break
                except subprocess.TimeoutExpired:
                    continue
        except WorkspaceError:
            raise
        except Exception:
            _terminate_popen(proc)
            raise

        stdout_file.seek(0)
        stderr_file.seek(0)
        stdout = stdout_file.read()
        stderr = stderr_file.read()

    if proc.returncode != 0:
        raise subprocess.CalledProcessError(proc.returncode, cmd, stdout, stderr)
    return subprocess.CompletedProcess(cmd, 0, stdout, stderr)


class WorkspaceError(RuntimeError):
    pass


def workspace_path(workspaces_root: Path, claim_key: str) -> Path:
    """Convert claim_key to a filesystem-safe path.

    Uses '--' between owner, repo, and PR number to avoid collisions
    between repos like 'a-b/c' and 'a/b-c'.
    """
    # claim_key is "owner/repo#42"; parse and use unambiguous separator.
    owner_repo, _, pr_num = claim_key.partition("#")
    owner, _, repo = owner_repo.partition("/")
    return workspaces_root / f"{owner}--{repo}--pr{pr_num}"


def _git_env(token: Token) -> dict[str, str]:
    """Build env dict with ephemeral git credential injection."""
    return git_credential_env(token)


def _safe_env() -> dict[str, str]:
    """Build a minimal env without secrets for local-only git operations."""
    return {k: os.environ[k] for k in _SAFE_ENV_VARS if k in os.environ}


def prepare(
    workspaces_root: Path,
    *,
    token: Token,
    repo_full_name: str,
    pr_number: int,
    head_ref: str,
    head_repo_full_name: str | None = None,
    shutdown_check: Callable[[], bool] | None = None,
) -> Path:
    """Ensure a workspace exists and is synced to origin/<head_ref>.

    For fork PRs, head_repo_full_name should be the fork's full_name
    so the clone targets the repo where the branch actually exists.

    If shutdown_check is provided, git subprocesses are polled and
    terminated early when shutdown_check() returns True.
    """
    workspaces_root.mkdir(parents=True, exist_ok=True)
    claim_key = f"{repo_full_name}#{pr_number}"
    path = workspace_path(workspaces_root, claim_key)
    env = _git_env(token)
    clone_repo = head_repo_full_name or repo_full_name
    clone_url = f"https://github.com/{clone_repo}.git"

    if not path.exists():
        logger.info("Cloning %s @ %s into %s", repo_full_name, head_ref, path)
        try:
            _run_git(
                [
                    "git", "clone",
                    "--branch", head_ref,
                    "--single-branch",
                    clone_url,
                    str(path),
                ],
                env=env,
                timeout=300,
                shutdown_check=shutdown_check,
            )
        except subprocess.CalledProcessError as e:
            # Clean up partial clone directory to avoid stale state
            if path.exists():
                shutil.rmtree(path, ignore_errors=True)
            raise WorkspaceError(
                f"git clone failed for {repo_full_name} (exit {e.returncode})"
            )
        except subprocess.TimeoutExpired:
            if path.exists():
                shutil.rmtree(path, ignore_errors=True)
            raise WorkspaceError(
                f"git clone timed out for {repo_full_name} after 300s"
            )
        except WorkspaceError:
            if path.exists():
                shutil.rmtree(path, ignore_errors=True)
            raise
    else:
        logger.info("Fetching %s in %s", head_ref, path)
        try:
            _run_git(
                [
                    "git", "-C", str(path),
                    "fetch", "origin",
                    f"refs/heads/{head_ref}:refs/remotes/origin/{head_ref}",
                ],
                env=env,
                timeout=120,
                shutdown_check=shutdown_check,
            )
            _run_git(
                [
                    "git", "-C", str(path),
                    "reset", "--hard", f"origin/{head_ref}",
                ],
                env=env,
                timeout=60,
                shutdown_check=shutdown_check,
            )
        except subprocess.CalledProcessError as e:
            raise WorkspaceError(
                f"git fetch/reset failed for {repo_full_name} (exit {e.returncode})"
            )
        except WorkspaceError:
            raise

    # Configure git identity for commits shft makes in this workspace.
    # Use scrubbed env — git config is a local-only operation, no secrets needed.
    safe = _safe_env()
    subprocess.run(
        ["git", "-C", str(path), "config", "user.name", "ctrl-shft bridge"],
        check=True,
        timeout=10,
        env=safe,
    )
    subprocess.run(
        ["git", "-C", str(path), "config", "user.email", "bridge@ctrlshft.local"],
        check=True,
        timeout=10,
        env=safe,
    )

    return path


def cleanup(workspaces_root: Path, claim_key: str) -> None:
    """Remove a workspace. Used when a PR is merged/closed."""
    path = workspace_path(workspaces_root, claim_key)
    if path.exists():
        shutil.rmtree(path)
