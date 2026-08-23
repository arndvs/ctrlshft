"""Unit tests for bridge/config.py — env loading and fail-fast validation.

Covers: Config.from_env() (allowlist filtering, worker-count guard, defaults,
optional creds, path derivation), require_webhook_secret() entropy check, and
require_github_app() fail-fast on missing app id / installation id / private key.

Run: python3 -m unittest discover -s test/python -p "test_bridge_config.py" -v
"""

import os
import sys
import unittest
from pathlib import Path
from unittest import mock

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT))

from bridge.config import Config, ConfigError

# Path.home() is evaluated while building Config defaults, so keep HOME present
# even when we clear the rest of the environment for isolation.
_HOME = os.path.expanduser("~")
_BASE = {"HOME": _HOME, "USERPROFILE": _HOME}
_MIN = {**_BASE, "BRIDGE_REPO_ALLOWLIST": "org/repo"}


def _env(**overrides):
    e = dict(_MIN)
    e.update(overrides)
    return e


class TestConfigFromEnv(unittest.TestCase):
    def test_minimal_valid_env(self):
        with mock.patch.dict(os.environ, _env(), clear=True):
            c = Config.from_env()
        self.assertEqual(c.repo_allowlist, ("org/repo",))
        self.assertEqual(c.webhook_port, 8765)
        self.assertEqual(c.max_iterations, 3)
        self.assertEqual(c.worker_count, 1)
        self.assertIsNone(c.github_app_id)
        self.assertIsNone(c.github_app_installation_id)
        self.assertIsNone(c.webhook_secret)

    def test_allowlist_filters_blanks_and_trailing_commas(self):
        with mock.patch.dict(os.environ, _env(BRIDGE_REPO_ALLOWLIST="a/b, ,c/d,"), clear=True):
            c = Config.from_env()
        self.assertEqual(c.repo_allowlist, ("a/b", "c/d"))

    def test_empty_allowlist_raises(self):
        with mock.patch.dict(os.environ, {**_BASE, "BRIDGE_REPO_ALLOWLIST": " , "}, clear=True):
            with self.assertRaises(ConfigError):
                Config.from_env()

    def test_missing_allowlist_raises(self):
        with mock.patch.dict(os.environ, dict(_BASE), clear=True):
            with self.assertRaises(ConfigError):
                Config.from_env()

    def test_worker_count_defaults_to_one(self):
        with mock.patch.dict(os.environ, _env(), clear=True):
            c = Config.from_env()
        self.assertEqual(c.worker_count, 1)

    def test_worker_count_accepts_multi(self):
        with mock.patch.dict(os.environ, _env(WORKER_COUNT="3"), clear=True):
            c = Config.from_env()
        self.assertEqual(c.worker_count, 3)

    def test_worker_count_rejects_non_positive(self):
        with mock.patch.dict(os.environ, _env(WORKER_COUNT="0"), clear=True):
            with self.assertRaises(ConfigError):
                Config.from_env()
        with mock.patch.dict(os.environ, _env(WORKER_COUNT="-1"), clear=True):
            with self.assertRaises(ConfigError):
                Config.from_env()

    def test_empty_bot_login_raises(self):
        with mock.patch.dict(os.environ, _env(COPILOT_BOT_LOGIN=""), clear=True):
            with self.assertRaises(ConfigError):
                Config.from_env()

    def test_custom_port_and_iterations(self):
        with mock.patch.dict(os.environ, _env(BRIDGE_PORT="9000", BRIDGE_MAX_ITERATIONS="5"), clear=True):
            c = Config.from_env()
        self.assertEqual(c.webhook_port, 9000)
        self.assertEqual(c.max_iterations, 5)

    def test_optional_creds_populated(self):
        with mock.patch.dict(
            os.environ,
            _env(GITHUB_APP_ID="123", GITHUB_APP_INSTALLATION_ID="456", WEBHOOK_SECRET="s" * 40),
            clear=True,
        ):
            c = Config.from_env()
        self.assertEqual(c.github_app_id, "123")
        self.assertEqual(c.github_app_installation_id, "456")
        self.assertEqual(c.webhook_secret, "s" * 40)

    def test_paths_derive_from_home_overrides(self):
        with mock.patch.dict(os.environ, _env(CTRLSHFT_HOME="/tmp/df", BRIDGE_ROOT="/tmp/br"), clear=True):
            c = Config.from_env()
        self.assertEqual(c.dotfiles_root, Path("/tmp/df"))
        self.assertEqual(c.db_path, Path("/tmp/br") / "state.db")
        self.assertEqual(c.workspaces_root, Path("/tmp/br") / "workspaces")


class TestRequireWebhookSecret(unittest.TestCase):
    def test_missing_raises(self):
        with mock.patch.dict(os.environ, _env(), clear=True):
            with self.assertRaises(ConfigError):
                Config.from_env().require_webhook_secret()

    def test_too_short_raises(self):
        with mock.patch.dict(os.environ, _env(WEBHOOK_SECRET="a" * 31), clear=True):
            with self.assertRaises(ConfigError):
                Config.from_env().require_webhook_secret()

    def test_exactly_32_ok(self):
        secret = "a" * 32
        with mock.patch.dict(os.environ, _env(WEBHOOK_SECRET=secret), clear=True):
            self.assertEqual(Config.from_env().require_webhook_secret(), secret)


class TestRequireGithubApp(unittest.TestCase):
    def test_missing_app_id_raises(self):
        with mock.patch.dict(
            os.environ,
            _env(GITHUB_APP_INSTALLATION_ID="456", GITHUB_APP_PRIVATE_KEY_B64="k"),
            clear=True,
        ):
            with self.assertRaises(ConfigError):
                Config.from_env().require_github_app()

    def test_missing_private_key_raises(self):
        with mock.patch.dict(
            os.environ,
            _env(GITHUB_APP_ID="123", GITHUB_APP_INSTALLATION_ID="456"),
            clear=True,
        ):
            with self.assertRaises(ConfigError):
                Config.from_env().require_github_app()

    def test_complete_returns_ids(self):
        with mock.patch.dict(
            os.environ,
            _env(GITHUB_APP_ID="123", GITHUB_APP_INSTALLATION_ID="456", GITHUB_APP_PRIVATE_KEY_B64="k"),
            clear=True,
        ):
            self.assertEqual(Config.from_env().require_github_app(), ("123", "456"))


if __name__ == "__main__":
    unittest.main()
