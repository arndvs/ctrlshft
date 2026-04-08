"""
preflight.py — Pre-run validation for portfolio showcaser.

Checks config, repo path, package manager, Node.js, port availability,
output directories, state file, and disk space before running.

Usage:
    from scripts.preflight import run_preflight

    ok, issues = run_preflight(config)
"""

from __future__ import annotations

import shutil
import socket
import subprocess
from pathlib import Path

from scripts.shared_utils import validate_config, validate_repo_path, check_command_available, detect_package_manager


def run_preflight(config: dict) -> tuple[bool, list[dict]]:
    """
    Run all preflight checks. Returns (all_passed, list_of_check_results).
    Each result: {name, passed, message, severity}
    Severity: 'error' blocks run, 'warning' allows run with caution.
    """
    checks = [
        _check_config(config),
        _check_repo_path(config),
        _check_package_json(config),
        _check_package_manager(config),
        _check_node(config),
        _check_port(config),
        _check_output_dirs(config),
        _check_state_file(config),
        _check_disk_space(config),
        _check_screenshots_dir(config),
    ]

    all_passed = all(c["passed"] or c["severity"] == "warning" for c in checks)

    return all_passed, checks


def _check_config(config: dict) -> dict:
    try:
        validate_config(config)
        return {"name": "Config validation", "passed": True, "message": "Config is valid", "severity": "error"}
    except ValueError as e:
        return {"name": "Config validation", "passed": False, "message": str(e), "severity": "error"}


def _check_repo_path(config: dict) -> dict:
    repo_path = config.get("repo_path", "")
    if not repo_path:
        return {"name": "Repo path", "passed": False, "message": "repo_path not set in config", "severity": "error"}

    try:
        validate_repo_path(repo_path)
        return {"name": "Repo path", "passed": True, "message": f"Repo exists at {repo_path}", "severity": "error"}
    except ValueError as e:
        return {"name": "Repo path", "passed": False, "message": str(e), "severity": "error"}


def _check_package_json(config: dict) -> dict:
    repo = Path(config.get("repo_path", ""))
    pkg_path = repo / "package.json"
    if pkg_path.exists():
        return {"name": "package.json", "passed": True, "message": "Found package.json", "severity": "error"}

    for alt in ["requirements.txt", "pyproject.toml", "composer.json", "Gemfile", "Cargo.toml", "go.mod"]:
        if (repo / alt).exists():
            return {"name": "Project manifest", "passed": True, "message": f"Found {alt}", "severity": "error"}

    return {"name": "package.json", "passed": False, "message": "No package.json or project manifest found", "severity": "error"}


def _check_package_manager(config: dict) -> dict:
    repo_path = config.get("repo_path", "")
    repo = Path(repo_path)
    pm = detect_package_manager(repo_path)

    if pm == "unknown":
        return {"name": "Package manager", "passed": True, "message": "Non-Node project, skipping", "severity": "warning"}

    if pm == "pip":
        return {"name": "Package manager", "passed": True, "message": "Python project (pip)", "severity": "warning"}

    if check_command_available(pm):
        return {"name": "Package manager", "passed": True, "message": f"{pm} detected and available", "severity": "error"}

    return {"name": "Package manager", "passed": False, "message": f"Lockfile requires {pm} but it's not installed", "severity": "error"}


def _check_node(config: dict) -> dict:
    repo = Path(config.get("repo_path", ""))
    if not (repo / "package.json").exists():
        return {"name": "Node.js", "passed": True, "message": "Non-Node project, skipping", "severity": "warning"}

    if not check_command_available("node"):
        return {"name": "Node.js", "passed": False, "message": "Node.js not found. Install from https://nodejs.org", "severity": "error"}

    try:
        result = subprocess.run(["node", "--version"], capture_output=True, text=True, timeout=10)
        version = result.stdout.strip()
        return {"name": "Node.js", "passed": True, "message": f"Node.js {version}", "severity": "error"}
    except (subprocess.TimeoutExpired, OSError):
        return {"name": "Node.js", "passed": False, "message": "Could not determine Node.js version", "severity": "warning"}


def _check_port(config: dict) -> dict:
    port = config.get("exploration", {}).get("port", 3000)
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(1)
            result = s.connect_ex(("localhost", port))
            if result == 0:
                return {"name": f"Port {port}", "passed": False, "message": f"Port {port} is already in use", "severity": "warning"}
            return {"name": f"Port {port}", "passed": True, "message": f"Port {port} is available", "severity": "warning"}
    except OSError:
        return {"name": f"Port {port}", "passed": True, "message": f"Port {port} appears available", "severity": "warning"}


def _check_output_dirs(config: dict) -> dict:
    output_dir = Path(config.get("output_dir", "./output"))
    try:
        output_dir.mkdir(parents=True, exist_ok=True)
        return {"name": "Output directory", "passed": True, "message": f"Output dir ready: {output_dir}", "severity": "error"}
    except OSError as e:
        return {"name": "Output directory", "passed": False, "message": f"Cannot create output dir: {e}", "severity": "error"}


def _check_state_file(config: dict) -> dict:
    state_path = Path(config.get("state_file", "./output/state.json"))
    if state_path.exists():
        return {"name": "State file", "passed": True, "message": f"Resuming from existing state: {state_path}", "severity": "warning"}
    return {"name": "State file", "passed": True, "message": "Fresh run (no existing state)", "severity": "warning"}


def _check_disk_space(config: dict) -> dict:
    output_dir = Path(config.get("output_dir", "./output"))
    target = output_dir if output_dir.exists() else Path(".")

    try:
        usage = shutil.disk_usage(target)
        free_gb = usage.free / (1024**3)
        if free_gb < 0.5:
            return {"name": "Disk space", "passed": False, "message": f"Only {free_gb:.1f}GB free — need at least 500MB for screenshots", "severity": "warning"}
        return {"name": "Disk space", "passed": True, "message": f"{free_gb:.1f}GB free", "severity": "warning"}
    except OSError:
        return {"name": "Disk space", "passed": True, "message": "Could not check disk space", "severity": "warning"}


def _check_screenshots_dir(config: dict) -> dict:
    screenshots_dir = Path(config.get("screenshots_dir", "./output/screenshots"))
    try:
        screenshots_dir.mkdir(parents=True, exist_ok=True)
        return {"name": "Screenshots directory", "passed": True, "message": f"Screenshots dir ready: {screenshots_dir}", "severity": "error"}
    except OSError as e:
        return {"name": "Screenshots directory", "passed": False, "message": f"Cannot create screenshots dir: {e}", "severity": "error"}


def print_preflight_results(checks: list[dict]) -> None:
    """Pretty-print preflight results for terminal output."""
    for check in checks:
        icon = "✅" if check["passed"] else ("⚠️" if check["severity"] == "warning" else "❌")
        print(f"  {icon} {check['name']}: {check['message']}")
