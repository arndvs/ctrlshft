"""Unit tests for bridge/webhook.py — the HMAC auth boundary and the
event/actor/state/allowlist filter chain that guards the enqueue path.

The FastAPI app's module globals (config, _webhook_secret) are normally set by
the lifespan handler; here we set them directly and drive the app with
fastapi.testclient.TestClient (no lifespan, no Config.from_env, no disk). db and
hud are mocked — no real database or HUD I/O.

Covers: _verify_signature() constant-time HMAC (valid / tampered / bad-prefix /
missing header), and POST /webhook — bad signature -> 401, disallowed event ->
204, invalid JSON -> 400, repo not in allowlist -> 204 (+ rejected HUD event),
non-Copilot actor -> 204, non-changes_requested review -> 204, [bot]-suffix
normalization, missing pr_number -> 400, happy path -> 202 (enqueue + received
HUD event), and duplicate delivery -> 202 with no HUD event.

Run: python3 -m unittest discover -s test/python -p "test_bridge_webhook.py" -v
"""

import hashlib
import hmac
import json
import sys
import types
import unittest
from pathlib import Path
from unittest import mock

from fastapi.testclient import TestClient

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT))

from bridge import webhook as wh

_SECRET = "s" * 40  # >= 32 chars, matches require_webhook_secret()'s floor


def _copilot_review_payload(
    *,
    repo="org/repo",
    actor="copilot-pull-request-reviewer[bot]",
    state="changes_requested",
    pr_number=42,
):
    return {
        "repository": {"full_name": repo},
        "review": {"user": {"login": actor}, "state": state},
        "pull_request": {"number": pr_number},
    }


class _WebhookBase(unittest.TestCase):
    def setUp(self):
        self.cfg = types.SimpleNamespace(
            repo_allowlist=("org/repo",),
            copilot_bot_login="copilot-pull-request-reviewer[bot]",
            hud_script=Path("/tmp/hud.sh"),
            db_path=Path("/tmp/state.db"),
        )
        # Install the module globals the lifespan handler would normally set.
        self._orig_config = wh.config
        self._orig_secret = wh._webhook_secret
        wh.config = self.cfg
        wh._webhook_secret = _SECRET
        self.addCleanup(setattr, wh, "config", self._orig_config)
        self.addCleanup(setattr, wh, "_webhook_secret", self._orig_secret)

        p_enq = mock.patch.object(wh.db, "enqueue")
        p_con = mock.patch.object(wh.db, "connect")
        p_hud = mock.patch.object(wh.hud, "emit")
        self.enqueue = p_enq.start()
        self.connect = p_con.start()
        self.hud_emit = p_hud.start()
        self.addCleanup(p_enq.stop)
        self.addCleanup(p_con.stop)
        self.addCleanup(p_hud.stop)
        self.enqueue.return_value = True

        self.client = TestClient(wh.app)

    def _sign(self, body: bytes) -> str:
        return "sha256=" + hmac.new(_SECRET.encode(), body, hashlib.sha256).hexdigest()

    def _post(self, body: bytes, *, event="pull_request_review", sig="__valid__",
              delivery="d1"):
        headers = {"X-GitHub-Event": event, "X-GitHub-Delivery": delivery}
        if sig == "__valid__":
            headers["X-Hub-Signature-256"] = self._sign(body)
        elif sig is not None:
            headers["X-Hub-Signature-256"] = sig
        # sig is None -> omit the signature header entirely
        return self.client.post("/webhook", content=body, headers=headers)


class TestVerifySignature(_WebhookBase):
    def test_valid_signature(self):
        body = b'{"a":1}'
        self.assertTrue(wh._verify_signature(body, self._sign(body)))

    def test_tampered_body_fails(self):
        # Signature computed over different bytes must not validate.
        self.assertFalse(wh._verify_signature(b'{"a":1}', self._sign(b'{"a":2}')))

    def test_missing_header_fails(self):
        self.assertFalse(wh._verify_signature(b"x", None))

    def test_wrong_algorithm_prefix_fails(self):
        # Only sha256= is accepted.
        body = b"x"
        digest = hmac.new(_SECRET.encode(), body, hashlib.sha256).hexdigest()
        self.assertFalse(wh._verify_signature(body, "sha1=" + digest))


class TestHealthz(_WebhookBase):
    def test_healthz_ok(self):
        resp = self.client.get("/healthz")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json(), {"status": "ok"})


class TestWebhookAuth(_WebhookBase):
    def test_bad_signature_returns_401(self):
        body = json.dumps(_copilot_review_payload()).encode()
        resp = self._post(body, sig="sha256=deadbeef")
        self.assertEqual(resp.status_code, 401)
        self.enqueue.assert_not_called()

    def test_missing_signature_returns_401(self):
        body = json.dumps(_copilot_review_payload()).encode()
        resp = self._post(body, sig=None)
        self.assertEqual(resp.status_code, 401)
        self.enqueue.assert_not_called()


class TestWebhookFiltering(_WebhookBase):
    def test_disallowed_event_returns_204(self):
        body = json.dumps(_copilot_review_payload()).encode()
        resp = self._post(body, event="push")
        self.assertEqual(resp.status_code, 204)
        self.enqueue.assert_not_called()

    def test_invalid_json_returns_400(self):
        body = b"not-json{"
        resp = self._post(body)  # valid signature over these exact bytes
        self.assertEqual(resp.status_code, 400)
        self.enqueue.assert_not_called()

    def test_repo_not_allowlisted_returns_204_and_emits_rejected(self):
        body = json.dumps(_copilot_review_payload(repo="evil/repo")).encode()
        resp = self._post(body)
        self.assertEqual(resp.status_code, 204)
        self.enqueue.assert_not_called()
        self.assertEqual(self.hud_emit.call_args.args[1], "bridge.webhook.rejected")

    def test_non_copilot_actor_returns_204(self):
        body = json.dumps(_copilot_review_payload(actor="random-human")).encode()
        resp = self._post(body)
        self.assertEqual(resp.status_code, 204)
        self.enqueue.assert_not_called()

    def test_non_changes_requested_review_returns_204(self):
        body = json.dumps(_copilot_review_payload(state="approved")).encode()
        resp = self._post(body)
        self.assertEqual(resp.status_code, 204)
        self.enqueue.assert_not_called()

    def test_missing_pr_number_returns_400(self):
        body = json.dumps(_copilot_review_payload(pr_number=None)).encode()
        resp = self._post(body)
        self.assertEqual(resp.status_code, 400)
        self.enqueue.assert_not_called()


class TestWebhookEnqueue(_WebhookBase):
    def test_happy_path_enqueues_and_returns_202(self):
        payload = _copilot_review_payload()
        body = json.dumps(payload).encode()
        resp = self._post(body, delivery="delivery-xyz")

        self.assertEqual(resp.status_code, 202)
        self.enqueue.assert_called_once()
        kwargs = self.enqueue.call_args.kwargs
        self.assertEqual(kwargs["delivery_id"], "delivery-xyz")
        self.assertEqual(kwargs["event_type"], "pull_request_review")
        self.assertEqual(kwargs["repo_full_name"], "org/repo")
        self.assertEqual(kwargs["pr_number"], 42)
        self.assertEqual(kwargs["payload"], payload)
        self.assertEqual(self.hud_emit.call_args.args[1], "bridge.webhook.received")

    def test_bot_suffix_normalization_still_enqueues(self):
        # Actor sent without the [bot] suffix must still match the configured
        # login that carries it.
        body = json.dumps(
            _copilot_review_payload(actor="copilot-pull-request-reviewer")
        ).encode()
        resp = self._post(body)
        self.assertEqual(resp.status_code, 202)
        self.enqueue.assert_called_once()

    def test_duplicate_delivery_returns_202_without_hud_event(self):
        self.enqueue.return_value = False  # already-seen delivery
        body = json.dumps(_copilot_review_payload()).encode()
        resp = self._post(body)
        self.assertEqual(resp.status_code, 202)
        self.enqueue.assert_called_once()
        self.hud_emit.assert_not_called()


if __name__ == "__main__":
    unittest.main()
