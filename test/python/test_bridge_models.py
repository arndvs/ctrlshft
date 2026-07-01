"""Unit tests for bridge/models.py — inbound webhook payload parsing.

Covers: PullRequestReviewEvent parses a realistic GitHub payload (ignoring
the many unmodeled fields), Review.state defaults to "", and missing
required fields raise ValidationError so the webhook can reject bad shapes
instead of crashing deep in the worker.

Run: python3 -m unittest discover -s test/python -p "test_bridge_models.py" -v
"""

import copy
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT))

from pydantic import ValidationError

from bridge.models import (
    PullRequest,
    PullRequestReviewEvent,
    Repository,
    Review,
    User,
)

# A realistic pull_request_review payload with many fields the bridge does
# NOT model — exercises pydantic's default "ignore extra fields" behavior.
_PAYLOAD = {
    "action": "submitted",
    "review": {
        "id": 123456,
        "node_id": "PRR_abc",
        "user": {"login": "copilot-pull-request-reviewer[bot]", "id": 99, "type": "Bot"},
        "body": "Please fix the null deref",
        "state": "changes_requested",
        "html_url": "https://github.com/org/repo/pull/7#pullrequestreview-123456",
        "submitted_at": "2026-06-29T00:00:00Z",
    },
    "pull_request": {
        "number": 7,
        "title": "Add feature",
        "html_url": "https://github.com/org/repo/pull/7",
        "state": "open",
        "head": {"ref": "ai/fix/x"},  # intentionally not modeled
    },
    "repository": {"full_name": "org/repo", "id": 555, "private": True},
    "sender": {"login": "octocat"},
    "installation": {"id": 1},
}


def _payload(mutate=None):
    p = copy.deepcopy(_PAYLOAD)
    if mutate:
        mutate(p)
    return p


class TestPullRequestReviewEvent(unittest.TestCase):
    def test_parses_realistic_payload(self):
        ev = PullRequestReviewEvent.model_validate(_payload())
        self.assertEqual(ev.action, "submitted")
        self.assertEqual(ev.review.user.login, "copilot-pull-request-reviewer[bot]")
        self.assertEqual(ev.review.state, "changes_requested")
        self.assertEqual(ev.pull_request.number, 7)
        self.assertEqual(ev.pull_request.title, "Add feature")
        self.assertEqual(ev.repository.full_name, "org/repo")

    def test_ignores_unmodeled_fields(self):
        # Lots of extra keys (sender, installation, review.id, pr.head, ...)
        # must not raise, and must not leak onto the model.
        ev = PullRequestReviewEvent.model_validate(_payload())
        self.assertNotIn("head", ev.pull_request.model_dump())
        self.assertNotIn("sender", ev.model_dump())

    def test_review_state_defaults_empty(self):
        ev = PullRequestReviewEvent.model_validate(
            _payload(lambda p: p["review"].pop("state"))
        )
        self.assertEqual(ev.review.state, "")

    def test_missing_action_raises(self):
        with self.assertRaises(ValidationError):
            PullRequestReviewEvent.model_validate(_payload(lambda p: p.pop("action")))

    def test_missing_review_raises(self):
        with self.assertRaises(ValidationError):
            PullRequestReviewEvent.model_validate(_payload(lambda p: p.pop("review")))

    def test_missing_nested_review_user_raises(self):
        with self.assertRaises(ValidationError):
            PullRequestReviewEvent.model_validate(
                _payload(lambda p: p["review"].pop("user"))
            )

    def test_missing_pr_number_raises(self):
        with self.assertRaises(ValidationError):
            PullRequestReviewEvent.model_validate(
                _payload(lambda p: p["pull_request"].pop("number"))
            )


class TestSubModels(unittest.TestCase):
    def test_user(self):
        self.assertEqual(User.model_validate({"login": "x"}).login, "x")

    def test_repository(self):
        self.assertEqual(Repository.model_validate({"full_name": "o/r"}).full_name, "o/r")

    def test_pull_request_requires_number(self):
        with self.assertRaises(ValidationError):
            PullRequest.model_validate({"title": "t", "html_url": "u"})

    def test_review_defaults_state(self):
        r = Review.model_validate({"user": {"login": "x"}, "html_url": "u"})
        self.assertEqual(r.state, "")


if __name__ == "__main__":
    unittest.main()
