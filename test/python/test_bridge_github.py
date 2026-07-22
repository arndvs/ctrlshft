"""Unit tests for bridge/github.py — token minting and GitHub API helpers.

subprocess (mint script) and the httpx client (_client) are mocked — no real
process or network I/O.

Covers: mint_token() success + error paths, fetch_unresolved_copilot_threads()
pagination and Copilot-author/resolved/outdated filtering (the "missed threads"
risk), fetch_pr_metadata() fork-aware head repo, and find_tracking_issue().

Run: python3 -m unittest discover -s test/python -p "test_bridge_github.py" -v
"""

import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT))

from bridge.github import (
    GitHubError,
    Token,
    fetch_pr_metadata,
    fetch_unresolved_copilot_threads,
    find_tracking_issue,
    mint_token,
)

_TOKEN = Token(value="ghs_test", expires_at="2026-01-01T00:00:00Z")


def _mock_client(json_payloads):
    """A context-manager httpx.Client stand-in.

    client.get and client.post EACH return the given JSON payloads in order,
    via independent side_effect sequences (raise_for_status is a no-op). Tests
    here use only one of get/post per client, so the two sequences never
    interleave; mix them only with that in mind.
    """
    client = mock.MagicMock()
    client.__enter__.return_value = client
    client.__exit__.return_value = False
    resps = []
    for payload in json_payloads:
        r = mock.MagicMock()
        r.json.return_value = payload
        r.raise_for_status.return_value = None
        resps.append(r)
    client.get.side_effect = list(resps)
    client.post.side_effect = list(resps)
    return client


# --- mint_token --------------------------------------------------------------

class TestMintToken(unittest.TestCase):
    def _run(self, **over):
        return mock.patch("bridge.github.subprocess.run", **over)

    def test_success_parses_token(self):
        cp = subprocess.CompletedProcess([], 0, '{"token":"t","expires_at":"e"}', "")
        with self._run(return_value=cp):
            tok = mint_token(Path("/fake/mint.py"))
        self.assertEqual(tok.value, "t")
        self.assertEqual(tok.expires_at, "e")

    def test_called_process_error_raises(self):
        err = subprocess.CalledProcessError(1, ["mint"], stderr="boom")
        with self._run(side_effect=err):
            with self.assertRaises(GitHubError):
                mint_token(Path("/fake/mint.py"))

    def test_timeout_raises(self):
        with self._run(side_effect=subprocess.TimeoutExpired(["mint"], 30)):
            with self.assertRaises(GitHubError):
                mint_token(Path("/fake/mint.py"))

    def test_invalid_json_raises(self):
        cp = subprocess.CompletedProcess([], 0, "not json", "")
        with self._run(return_value=cp):
            with self.assertRaises(GitHubError):
                mint_token(Path("/fake/mint.py"))

    def test_missing_field_raises(self):
        # Exercise both sides of `if not token or not expires_at`.
        for stdout in ('{"token":"t"}', '{"expires_at":"e"}'):
            cp = subprocess.CompletedProcess([], 0, stdout, "")
            with self._run(return_value=cp):
                with self.assertRaises(GitHubError):
                    mint_token(Path("/fake/mint.py"))


# --- fetch_unresolved_copilot_threads ---------------------------------------

def _thread(tid="T1", resolved=False, outdated=False, author="copilot",
            with_comment=True, path="src/a.py", line=5):
    comments = []
    if with_comment:
        comments = [{
            "id": "C1", "body": "please fix", "path": path, "line": line,
            "diffHunk": "@@ -1 +1 @@", "url": "https://x/thread",
            "author": {"login": author},
        }]
    return {"id": tid, "isResolved": resolved, "isOutdated": outdated,
            "comments": {"nodes": comments}}


def _page(nodes, has_next=False, cursor=None):
    return {"data": {"repository": {"pullRequest": {"reviewThreads": {
        "pageInfo": {"hasNextPage": has_next, "endCursor": cursor},
        "nodes": nodes,
    }}}}}


class TestFetchUnresolvedThreads(unittest.TestCase):
    def _fetch(self, pages):
        with mock.patch("bridge.github._client", return_value=_mock_client(pages)):
            return fetch_unresolved_copilot_threads(
                _TOKEN, owner="org", repo="repo", pr_number=7, copilot_login="copilot"
            )

    def test_returns_copilot_unresolved_thread(self):
        out = self._fetch([_page([_thread()])])
        self.assertEqual(len(out), 1)
        self.assertEqual(out[0].thread_id, "T1")
        self.assertEqual(out[0].path, "src/a.py")
        self.assertEqual(out[0].author, "copilot")
        self.assertEqual(out[0].diff_hunk, "@@ -1 +1 @@")

    def test_filters_resolved_outdated_nonauthor_and_empty(self):
        nodes = [
            _thread(tid="keep"),                       # copilot, unresolved → keep
            _thread(tid="res", resolved=True),         # resolved → drop
            _thread(tid="old", outdated=True),         # outdated → drop
            _thread(tid="human", author="somebody"),   # not copilot → drop
            _thread(tid="empty", with_comment=False),  # no comments → drop
        ]
        out = self._fetch([_page(nodes)])
        self.assertEqual([t.thread_id for t in out], ["keep"])

    def test_paginates_and_threads_cursor(self):
        pages = [
            _page([_thread(tid="p1")], has_next=True, cursor="c1"),
            _page([_thread(tid="p2")], has_next=False),
        ]
        client = _mock_client(pages)
        with mock.patch("bridge.github._client", return_value=client):
            out = fetch_unresolved_copilot_threads(
                _TOKEN, owner="org", repo="repo", pr_number=7, copilot_login="copilot"
            )
        self.assertEqual(sorted(t.thread_id for t in out), ["p1", "p2"])
        # Page 2 must forward page 1's endCursor — otherwise a cursor regression
        # would refetch page 1 forever. Assert the second request's cursor.
        calls = client.post.call_args_list
        self.assertEqual(len(calls), 2)
        self.assertIsNone(calls[0].kwargs["json"]["variables"]["cursor"])
        self.assertEqual(calls[1].kwargs["json"]["variables"]["cursor"], "c1")

    def test_graphql_errors_raise(self):
        with mock.patch("bridge.github._client", return_value=_mock_client([{"errors": [{"message": "boom"}]}])):
            with self.assertRaises(GitHubError):
                fetch_unresolved_copilot_threads(
                    _TOKEN, owner="org", repo="repo", pr_number=7, copilot_login="copilot"
                )


# --- fetch_pr_metadata -------------------------------------------------------

class TestFetchPrMetadata(unittest.TestCase):
    def _fetch(self, payload):
        with mock.patch("bridge.github._client", return_value=_mock_client([payload])):
            return fetch_pr_metadata(_TOKEN, owner="org", repo="repo", pr_number=7)

    def test_fork_aware_head_repo(self):
        md = self._fetch({
            "head": {"ref": "feature", "repo": {"full_name": "fork/repo"}},
            "title": "Add feature", "html_url": "https://x/pr/7",
        })
        self.assertEqual(md.head_ref, "feature")
        self.assertEqual(md.head_repo_full_name, "fork/repo")
        self.assertEqual(md.title, "Add feature")

    def test_missing_head_repo_falls_back_to_base(self):
        md = self._fetch({
            "head": {"ref": "feature", "repo": None},  # deleted fork
            "title": "T", "html_url": "u",
        })
        self.assertEqual(md.head_repo_full_name, "org/repo")


# --- find_tracking_issue -----------------------------------------------------

class TestFindTrackingIssue(unittest.TestCase):
    def test_returns_first_match(self):
        with mock.patch("bridge.github._client", return_value=_mock_client([{"items": [{"number": 5}, {"number": 6}]}])):
            issue = find_tracking_issue(_TOKEN, owner="org", repo="repo", marker="<!-- m -->")
        self.assertEqual(issue["number"], 5)

    def test_returns_none_when_empty(self):
        with mock.patch("bridge.github._client", return_value=_mock_client([{"items": []}])):
            issue = find_tracking_issue(_TOKEN, owner="org", repo="repo", marker="<!-- m -->")
        self.assertIsNone(issue)


# --- Token repr redaction ----------------------------------------------------

class TestTokenRepr(unittest.TestCase):
    def test_repr_redacts_value(self):
        tok = Token(value="ghs_supersecret123", expires_at="2026-01-01T00:00:00Z")
        r = repr(tok)
        self.assertNotIn("ghs_supersecret123", r)
        self.assertIn("<redacted>", r)
        self.assertIn("2026-01-01T00:00:00Z", r)


# --- _client authentication header ------------------------------------------

class TestClientAuthHeader(unittest.TestCase):
    def test_bearer_uses_token_value(self):
        """Regression: Authorization header must use the real token, not a placeholder."""
        from bridge.github import _client

        tok = Token(value="ghs_real_token_abc", expires_at="2026-12-31T00:00:00Z")
        client = _client(tok)
        auth_header = client.headers["authorization"]
        self.assertEqual(auth_header, "Bearer ghs_real_token_abc")
        client.close()

    def test_bearer_not_literal_placeholder(self):
        """Fails if someone hard-codes a placeholder string."""
        from bridge.github import _client

        tok = Token(value="ghs_dynamic_value", expires_at="2026-12-31T00:00:00Z")
        client = _client(tok)
        auth_header = client.headers["authorization"]
        # Must not be a static/placeholder value
        self.assertNotIn("placeholder", auth_header.lower())
        self.assertNotIn("token_here", auth_header.lower())
        self.assertIn("ghs_dynamic_value", auth_header)
        client.close()


class TestMintTokenShutdown(unittest.TestCase):
    """Test shutdown-aware mint_token with shutdown_check callback."""

    def test_shutdown_during_mint_raises_github_error(self):
        """When shutdown_check returns True, mint terminates the child and raises."""
        proc = mock.MagicMock()
        proc.poll.return_value = None
        proc.pid = 1234
        proc.wait.side_effect = subprocess.TimeoutExpired("cmd", 0.5)

        with mock.patch("bridge.github.subprocess.Popen", return_value=proc), \
                mock.patch("bridge.github.terminate_process_group") as terminate, \
                mock.patch("bridge.github._time.monotonic", return_value=0):
            with self.assertRaises(GitHubError) as ctx:
                mint_token(Path("/mint"), shutdown_check=lambda: True)

        self.assertIn("shutdown", str(ctx.exception))
        terminate.assert_called_once_with(proc)

    def test_mint_completes_when_no_shutdown(self):
        """Normal completion with shutdown_check that never fires."""
        proc = mock.MagicMock()
        proc.poll.return_value = None
        proc.pid = 1234
        proc.returncode = 0
        proc.wait.return_value = None  # exits immediately

        def fake_popen(*args, **kwargs):
            kwargs["stdout"].write('{"token":"ghs_x","expires_at":"2026-01-01T00:00:00Z"}')
            kwargs["stdout"].flush()
            return proc

        with mock.patch("bridge.github.subprocess.Popen", side_effect=fake_popen), \
                mock.patch("bridge.github._time.monotonic", return_value=0):
            token = mint_token(Path("/mint"), shutdown_check=lambda: False)

        self.assertEqual(token.value, "ghs_x")

    def test_mint_timeout_with_shutdown_check(self):
        """Timeout still works when shutdown_check is provided."""
        proc = mock.MagicMock()
        proc.poll.return_value = None
        proc.pid = 1234
        proc.wait.side_effect = subprocess.TimeoutExpired("cmd", 0.5)

        with mock.patch("bridge.github.subprocess.Popen", return_value=proc), \
                mock.patch("bridge.github.terminate_process_group") as terminate, \
                mock.patch("bridge.github._time.monotonic", side_effect=[0, 31]):
            with self.assertRaises(GitHubError) as ctx:
                mint_token(Path("/mint"), shutdown_check=lambda: False)

        self.assertIn("timed out", str(ctx.exception))
        terminate.assert_called_once_with(proc)


if __name__ == "__main__":
    unittest.main()
