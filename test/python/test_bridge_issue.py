"""Unit tests for bridge/issue.py — tracking-issue title/body construction.

Covers: marker() format, title() truncation, body() structure, thread
location rendering, and 65K body truncation that preserves the trailing
marker so the bridge can still find the issue.

Run: python3 -m unittest discover -s test/python -p "test_bridge_issue.py" -v
"""

import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT))

from bridge import issue
from bridge.github import UnresolvedThread


def _thread(
    thread_id="t1",
    url="https://example.test/thread/1",
    path="src/a.py",
    line=10,
    body="Fix this null deref",
    diff_hunk="@@ -1 +1 @@",
    author="copilot",
):
    return UnresolvedThread(
        thread_id=thread_id, url=url, path=path, line=line,
        body=body, diff_hunk=diff_hunk, author=author,
    )


class TestMarker(unittest.TestCase):
    def test_format(self):
        self.assertEqual(
            issue.marker("org/repo", 42), "<!-- copilot-bridge:pr-org/repo#42 -->"
        )


class TestTitle(unittest.TestCase):
    def test_normal(self):
        self.assertEqual(issue.title(42, "Add feature"), "[copilot-review] PR #42: Add feature")

    def test_truncates_long_title_with_ellipsis(self):
        t = issue.title(1, "x" * 500)
        self.assertLessEqual(len(t), issue.MAX_TITLE_LEN)
        self.assertTrue(t.endswith("\u2026"))


class TestBody(unittest.TestCase):
    def _body(self, threads=None):
        return issue.body(
            repo_full_name="org/repo",
            pr_number=7,
            pr_url="https://example.test/pr/7",
            branch="ai/fix/x",
            review_event_url="https://example.test/review",
            threads=[_thread()] if threads is None else threads,
        )

    def test_contains_source_and_trailing_marker(self):
        b = self._body()
        self.assertIn("https://example.test/pr/7", b)
        self.assertIn("`ai/fix/x`", b)
        self.assertTrue(b.rstrip().endswith(issue.marker("org/repo", 7)))

    def test_thread_location_and_diff_rendered(self):
        b = self._body([_thread(path="src/a.py", line=10)])
        self.assertIn("src/a.py:10", b)
        self.assertIn("@@ -1 +1 @@", b)

    def test_thread_without_location(self):
        b = self._body([_thread(path=None, line=None, diff_hunk=None)])
        self.assertIn("(no location)", b)

    def test_instruction_block_is_compressed_but_preserves_contract(self):
        b = self._body()
        instructions = b.split("## Instructions\n", 1)[1].split(issue.marker("org/repo", 7), 1)[0]
        instruction_lines = [line for line in instructions.strip().splitlines() if line.strip()]
        self.assertLessEqual(len(instruction_lines), 4)
        self.assertIn("atomic commit", instructions)
        self.assertIn("Fixed in <sha>", instructions)
        self.assertIn("resolve via GraphQL", instructions)
        self.assertIn("relabel `hitl`", instructions)
        self.assertIn("close this issue", instructions)

    def test_truncates_oversized_body_preserving_marker(self):
        b = self._body([_thread(body="z" * 100000)])
        self.assertLessEqual(len(b), issue.MAX_BODY_LEN)
        self.assertIn("Body truncated", b)
        self.assertTrue(b.rstrip().endswith(issue.marker("org/repo", 7)))


if __name__ == "__main__":
    unittest.main()
