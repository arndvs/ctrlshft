"""
email_handler.py — Inbox polling for citation directory verification emails.

Supports IMAP (any provider) and Gmail API. Gmail API requires domain-wide
delegation with a subject user — see references/setup.md for configuration.

Usage:
    from scripts.email_handler import EmailHandler
    handler = EmailHandler(config)
    url = handler.wait_for_verification_email("yelp.com", submitted_after=datetime.now())
"""

import imaplib
import email as email_lib
import os
import re
import time
from datetime import datetime
from typing import Optional

from scripts.shared_utils import discover_credentials


class EmailHandler:
    def __init__(self, config: dict):
        self.config = config
        self.email_cfg = config["email"]
        self.use_gmail_api = self.email_cfg.get("use_gmail_api", False)
        self.poll_interval = self.email_cfg.get("poll_interval_seconds", 60)
        self.max_poll_minutes = self.email_cfg.get("max_poll_minutes", 15)

    def wait_for_verification_email(
        self, sender_domain: str, submitted_after: datetime
    ) -> Optional[str]:
        """
        Poll inbox for a verification email from sender_domain.
        Returns the verification URL if found, or None on timeout.
        """
        deadline = time.time() + (self.max_poll_minutes * 60)
        attempt = 0
        seen_ids: set[str] = set()

        while time.time() < deadline:
            attempt += 1
            print(f"  Email poll attempt {attempt} for {sender_domain}...")
            try:
                url = self._check_inbox(sender_domain, submitted_after, seen_ids)
                if url:
                    print(f"  ✓ Verification URL found for {sender_domain}")
                    return url
            except (EnvironmentError, ValueError) as e:
                raise
            except Exception as e:
                print(f"  Email check error: {e}")

            remaining = int((deadline - time.time()) / 60)
            print(f"  No email yet. {remaining}m remaining. Waiting {self.poll_interval}s...")
            time.sleep(self.poll_interval)

        print(f"  Timeout: No verification email from {sender_domain} after {self.max_poll_minutes}m.")
        return None

    def _check_inbox(self, sender_domain: str, submitted_after: datetime, seen_ids: set[str] = None) -> Optional[str]:
        if seen_ids is None:
            seen_ids = set()
        if self.use_gmail_api:
            return self._check_gmail_api(sender_domain, submitted_after, seen_ids)
        return self._check_imap(sender_domain, submitted_after, seen_ids)

    # ── IMAP ───────────────────────────────────────────────────────────────────

    def _check_imap(self, sender_domain: str, submitted_after: datetime, seen_ids: set[str]) -> Optional[str]:
        host = os.environ.get("CITATION_IMAP_HOST", "imap.gmail.com")

        user = os.environ.get("CITATION_EMAIL", "")
        if not user:
            raise EnvironmentError(
                "CITATION_EMAIL environment variable is not set.\n"
                "Set it with: export CITATION_EMAIL='citations@yourdomain.com'"
            )

        password = os.environ.get("CITATION_EMAIL_PASSWORD", "")
        if not password:
            raise EnvironmentError(
                "CITATION_EMAIL_PASSWORD environment variable is not set.\n"
                "Set it with: export CITATION_EMAIL_PASSWORD='your-password'"
            )

        mail = imaplib.IMAP4_SSL(host)
        try:
            try:
                mail.login(user, password)
            except imaplib.IMAP4.error:
                raise EnvironmentError(
                    f"IMAP login failed for {user} — check CITATION_EMAIL_PASSWORD"
                )
            mail.select("INBOX")
            safe_domain = re.sub(r'[^a-zA-Z0-9.\-]', '', sender_domain)
            date_str = submitted_after.strftime("%d-%b-%Y")
            _, data = mail.search(None, f'FROM "@{safe_domain}" SINCE "{date_str}"')
            for num in data[0].split():
                uid = num.decode() if isinstance(num, bytes) else str(num)
                if uid in seen_ids:
                    continue
                seen_ids.add(uid)
                _, msg_data = mail.fetch(num, "(RFC822)")
                raw = msg_data[0][1]
                msg = email_lib.message_from_bytes(raw)
                url = self._extract_verification_url(msg, sender_domain)
                if url:
                    return url
        finally:
            try:
                mail.logout()
            except Exception:
                pass
        return None

    # ── Gmail API ─────────────────────────────────────────────────────────────

    def _check_gmail_api(self, sender_domain: str, submitted_after: datetime, seen_ids: set[str]) -> Optional[str]:
        """
        Gmail API via service account with domain-wide delegation.
        Requires 'gmail_subject_user' in config["email"] — the Google Workspace
        user whose inbox to access. Service accounts cannot use userId='me'
        without delegation + subject.
        """
        from google.oauth2 import service_account as sa_module
        from googleapiclient.discovery import build

        subject_user = self.email_cfg.get("gmail_subject_user")
        if not subject_user:
            raise ValueError(
                "Gmail API requires 'gmail_subject_user' in config email settings. "
                "This must be a Google Workspace user email address. "
                "See references/setup.md → Gmail API section."
            )

        creds_file = discover_credentials(self.config)
        creds = sa_module.Credentials.from_service_account_file(
            creds_file,
            scopes=["https://www.googleapis.com/auth/gmail.readonly"],
        ).with_subject(subject_user)  # required for domain-wide delegation

        service = build("gmail", "v1", credentials=creds)
        after_ts = int(submitted_after.timestamp())
        query = (
            f"from:@{sender_domain} after:{after_ts} "
            f"subject:(verify OR confirm OR activate OR claim)"
        )

        results = service.users().messages().list(userId="me", q=query).execute()
        messages = results.get("messages", [])

        for msg_ref in messages:
            msg_id = msg_ref["id"]
            if msg_id in seen_ids:
                continue
            seen_ids.add(msg_id)
            msg = service.users().messages().get(
                userId="me", id=msg_ref["id"], format="full"
            ).execute()
            body = _extract_gmail_body(msg)
            if body:
                url = _find_verification_url_in_text(body, sender_domain)
                if url:
                    return url

        return None

    # ── URL extraction ─────────────────────────────────────────────────────────

    def _extract_verification_url(self, msg, sender_domain: str) -> Optional[str]:
        """Extract verification URL from an email.Message object."""
        body_parts = []

        if msg.is_multipart():
            for part in msg.walk():
                ct = part.get_content_type()
                if ct in ("text/html", "text/plain"):
                    payload = part.get_payload(decode=True)
                    if payload:
                        body_parts.append(payload.decode(errors="replace"))
        else:
            payload = msg.get_payload(decode=True)
            if payload:
                body_parts.append(payload.decode(errors="replace"))

        full_body = "\n".join(body_parts)
        return _find_verification_url_in_text(full_body, sender_domain)


def _find_verification_url_in_text(text: str, sender_domain: str) -> Optional[str]:
    """Find a verification URL in raw text. Checks domain-specific, then href-context, then generic path patterns."""
    domain_escaped = re.escape(sender_domain)
    url_char = r'[^\s"\'<>]'

    # Priority 1: URL contains sender domain + verification path keyword
    domain_patterns = [
        rf'https?://{url_char}*{domain_escaped}{url_char}*/verif{url_char}*',
        rf'https?://{url_char}*{domain_escaped}{url_char}*/confirm{url_char}*',
        rf'https?://{url_char}*{domain_escaped}{url_char}*/activ{url_char}*',
        rf'https?://{url_char}*{domain_escaped}{url_char}*/claim{url_char}*',
        rf'https?://{url_char}*{domain_escaped}{url_char}*/validate{url_char}*',
    ]

    for pattern in domain_patterns:
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            return match.group(0).rstrip(".,;)>\"'")

    # Priority 2: href link near verification keywords (catches ESP tracking redirects)
    href_pattern = re.compile(
        r'href\s*=\s*["\']?(https?://[^\s"\'<>]+)["\']?',
        re.IGNORECASE,
    )
    verify_keywords = re.compile(
        r'verif|confirm|activat|claim|validate',
        re.IGNORECASE,
    )

    for match in href_pattern.finditer(text):
        url = match.group(1).rstrip(".,;)>\"'")
        start = max(0, match.start() - 200)
        end   = min(len(text), match.end() + 200)
        context = text[start:end]

        if verify_keywords.search(context):
            return url

    # Priority 3: Any URL with a verification-like path segment (last resort)
    generic_pattern = re.compile(
        rf'https?://{url_char}*(?:/verify|/confirm|/activate|/claim|/validate|/click){url_char}*',
        re.IGNORECASE,
    )
    match = generic_pattern.search(text)

    if match:
        return match.group(0).rstrip(".,;)>\"'")

    return None


def _extract_gmail_body(msg: dict) -> str:
    """Extract decoded text/html body from a Gmail API message dict."""
    import base64

    def decode_data(data: str) -> str:
        if not data:
            return ""
        padded = data + "=" * (4 - len(data) % 4)
        return base64.urlsafe_b64decode(padded).decode(errors="replace")

    payload = msg.get("payload", {})

    # Single-part message
    if "body" in payload and payload["body"].get("data"):
        return decode_data(payload["body"]["data"])

    # Multipart — walk parts
    parts = payload.get("parts", [])
    html_body = ""
    text_body = ""
    for part in _walk_gmail_parts(parts):
        mime = part.get("mimeType", "")
        data = part.get("body", {}).get("data", "")
        if mime == "text/html" and data:
            html_body = decode_data(data)
        elif mime == "text/plain" and data and not html_body:
            text_body = decode_data(data)

    return html_body or text_body


def _walk_gmail_parts(parts: list) -> list:
    """Recursively flatten Gmail API message parts."""
    result = []
    for part in parts:
        result.append(part)
        if "parts" in part:
            result.extend(_walk_gmail_parts(part["parts"]))
    return result
