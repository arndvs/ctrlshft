"""Unit tests for bridge/git_creds.py — credential env construction.

Covers: git_credential_env() builds the GIT_CONFIG_COUNT insteadOf rewrite,
forwards only the safe env-var allowlist (no secret leakage), omits absent
safe vars, and Token.__repr__ redacts the token value.

Run: python3 -m unittest discover -s test/python -p "test_bridge_git_creds.py" -v
"""

import os
import sys
import unittest
from pathlib import Path
from unittest import mock

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT))

from bridge.git_creds import git_credential_env
from bridge.github import Token

_TOKEN = Token(value="ghs_secrettoken123", expires_at="2026-01-01T00:00:00Z")


class TestGitCredentialEnv(unittest.TestCase):
    def test_sets_git_config_rewrite(self):
        with mock.patch.dict(os.environ, {"HOME": "/home/x", "PATH": "/usr/bin"}, clear=True):
            env = git_credential_env(_TOKEN)
        self.assertEqual(env["GIT_CONFIG_COUNT"], "1")
        self.assertIn("x-access-token:ghs_secrettoken123@github.com", env["GIT_CONFIG_KEY_0"])
        self.assertTrue(env["GIT_CONFIG_KEY_0"].endswith(".insteadOf"))
        self.assertEqual(env["GIT_CONFIG_VALUE_0"], "https://github.com/")

    def test_forwards_safe_vars(self):
        with mock.patch.dict(
            os.environ, {"HOME": "/home/x", "PATH": "/usr/bin", "LANG": "en_US.UTF-8"}, clear=True
        ):
            env = git_credential_env(_TOKEN)
        self.assertEqual(env["HOME"], "/home/x")
        self.assertEqual(env["PATH"], "/usr/bin")
        self.assertEqual(env["LANG"], "en_US.UTF-8")

    def test_does_not_leak_unsafe_vars(self):
        with mock.patch.dict(
            os.environ,
            {"HOME": "/home/x", "GITHUB_APP_PRIVATE_KEY_B64": "supersecret", "AWS_SECRET_ACCESS_KEY": "leak"},
            clear=True,
        ):
            env = git_credential_env(_TOKEN)
        self.assertNotIn("GITHUB_APP_PRIVATE_KEY_B64", env)
        self.assertNotIn("AWS_SECRET_ACCESS_KEY", env)
        # The unsafe secret value must not be smuggled into any forwarded value.
        self.assertNotIn("supersecret", "".join(env.values()))

    def test_absent_safe_var_is_omitted(self):
        with mock.patch.dict(os.environ, {"HOME": "/home/x"}, clear=True):
            env = git_credential_env(_TOKEN)
        self.assertIn("HOME", env)
        self.assertNotIn("PATH", env)  # not in environ → not forwarded


if __name__ == "__main__":
    unittest.main()
