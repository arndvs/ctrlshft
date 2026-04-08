"""
app_runner.py — Dev server lifecycle manager.

Installs dependencies, starts the dev server, waits for it to be ready,
and provides a clean shutdown. The VS Code agent calls these methods;
this module never touches a browser.

Usage:
    from scripts.app_runner import AppRunner

    runner = AppRunner(config, analysis)
    runner.install_deps()
    runner.start()
    # ... agent does browser work ...
    runner.stop()
"""

from __future__ import annotations

import os
import signal
import subprocess
import sys
import time
from pathlib import Path


class AppRunner:
    """
    Agent: This class manages the development server lifecycle.
    Call install_deps() first, then start(), then stop() when done.
    If the server fails to start, check the error output and ensure
    the project's dependencies are installed and env vars are set.
    """

    def __init__(self, config: dict, analysis: dict):
        self.repo_path = config["repo_path"]
        self.port = config.get("exploration", {}).get("port") or analysis.get("dev_port", 3000)
        self.timeout = config.get("exploration", {}).get("dev_server_timeout", 120)
        self.start_command = analysis.get("start_command", "")
        self.package_manager = analysis.get("package_manager", "npm")
        self._process: subprocess.Popen | None = None
        self._started = False

    @property
    def base_url(self) -> str:
        return f"http://localhost:{self.port}"

    @property
    def is_running(self) -> bool:
        if self._process is None:
            return False
        return self._process.poll() is None

    def install_deps(self) -> str:
        """
        Agent: Run this before start(). Installs project dependencies
        using the detected package manager. Returns stdout on success,
        raises RuntimeError on failure.
        """
        install_commands = {
            "npm": "npm install",
            "yarn": "yarn install",
            "pnpm": "pnpm install",
            "bun": "bun install",
            "pip": "pip install -r requirements.txt",
        }

        cmd = install_commands.get(self.package_manager)
        if not cmd:
            return f"No install command for package manager: {self.package_manager}"

        result = subprocess.run(
            cmd,
            shell=True,
            cwd=self.repo_path,
            capture_output=True,
            text=True,
            timeout=300,
        )

        if result.returncode != 0:
            raise RuntimeError(
                f"Dependency install failed (exit {result.returncode}):\n{result.stderr[:2000]}"
            )

        return result.stdout[:1000]

    def start(self) -> str:
        """
        Agent: Start the dev server. Returns the base URL when ready.
        Raises RuntimeError if the server doesn't respond within timeout.
        """
        if not self.start_command:
            raise RuntimeError("No start command detected. Set it in config or check code_analyzer output.")

        if self._process and self.is_running:
            return self.base_url

        env = os.environ.copy()
        env["PORT"] = str(self.port)
        env["NODE_ENV"] = "development"

        self._process = subprocess.Popen(
            self.start_command,
            shell=True,
            cwd=self.repo_path,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            creationflags=subprocess.CREATE_NEW_PROCESS_GROUP if sys.platform == "win32" else 0,
        )

        if not self._wait_for_ready():
            stderr_output = ""
            try:
                stderr_output = self._process.stderr.read(2000) if self._process.stderr else ""
            except Exception:
                pass
            self.stop()
            raise RuntimeError(
                f"Dev server did not become ready within {self.timeout}s.\n"
                f"Command: {self.start_command}\n"
                f"Stderr: {stderr_output}"
            )

        self._started = True
        return self.base_url

    def stop(self) -> None:
        """
        Agent: Stop the dev server and clean up. Safe to call multiple times.
        """
        if self._process is None:
            return

        try:
            if sys.platform == "win32":
                self._process.send_signal(signal.CTRL_BREAK_EVENT)
            else:
                os.killpg(os.getpgid(self._process.pid), signal.SIGTERM)
        except (ProcessLookupError, OSError):
            pass

        try:
            self._process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self._process.kill()
            self._process.wait(timeout=5)

        self._process = None
        self._started = False

    def _wait_for_ready(self) -> bool:
        """Poll localhost:port until it responds or timeout."""
        import urllib.request
        import urllib.error

        deadline = time.time() + self.timeout
        url = self.base_url

        while time.time() < deadline:
            if self._process and self._process.poll() is not None:
                return False

            try:
                req = urllib.request.Request(url, method="HEAD")
                with urllib.request.urlopen(req, timeout=3):
                    return True
            except (urllib.error.URLError, OSError, ConnectionError):
                pass

            time.sleep(2)

        return False

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.stop()
        return False
