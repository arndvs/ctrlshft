"""
sheets_client.py — Google Sheets read/write wrapper for citation campaign tracking.

Auth: Uses service account JSON auto-discovered from ~/dotfiles/secrets/*.json
per google-docs.instructions.md. Requires the venv at ~/dotfiles/secrets/.venv
to be active before running any script that imports this module.

Usage:
    from scripts.sheets_client import SheetsClient
    client = SheetsClient(config)
    domains = client.get_pending_domains()
    client.set_status(row_index=2, status="submitted", notes="Confirmation #12345")
"""

import time
from datetime import datetime, timedelta

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

from scripts.shared_utils import discover_credentials, NOTE_MAX_LEN

SCOPES = ["https://www.googleapis.com/auth/spreadsheets"]

# Status codes — single source of truth (matches SKILL.md)
STATUS_CODES = {
    "not_started", "in_progress", "submitted", "email_verification_pending",
    "pending_review", "verified", "verified_partial", "nap_mismatch",
    "duplicate", "needs_claim", "paid_only", "manual_needed",
    "captcha_required", "failed", "delisted", "partial_submission", "already_listed"
}

# Statuses that mean "done — do not reprocess on campaign start"
# Matches SKILL.md Phase 0 startup skip rules exactly.
SKIP_ON_STARTUP = {"verified", "duplicate", "paid_only", "manual_needed", "already_listed"}

# Column index mapping (0-based, A=0 ... V=21)
COL = {
    "domain":              0,
    "priority":            1,
    "da_score":            2,
    "category":            3,
    "platform_type":       4,
    "difficulty":          5,
    "captcha_type":        6,
    "submission_url":      7,
    "status":              8,
    "email_used":          9,
    "username":            10,
    "date_submitted":      11,
    "date_verified":       12,
    "listing_url":         13,
    "confirmation_id":     14,
    "nap_match_score":     15,
    "verification_method": 16,
    "evidence_path":       17,
    "last_checked":        18,
    "next_check_due":      19,
    "notes":               20,
    "cost_gate":           21,
}

HEADERS = [
    "Domain", "Priority", "DA Score", "Category", "Platform Type",
    "Difficulty", "CAPTCHA Type", "Submission URL", "Status",
    "Email Used", "Username", "Date Submitted", "Date Verified",
    "Listing URL", "Confirmation ID", "NAP Match Score",
    "Verification Method", "Evidence Path", "Last Checked",
    "Next Check Due", "Notes", "Cost Gate (Paid Only)",
]


_MAX_RETRIES = 5
_BACKOFF_BASE = 2


def _execute_with_retry(request):
    """Execute a Google Sheets API request with exponential backoff on 429."""
    for attempt in range(_MAX_RETRIES):
        try:
            return request.execute()
        except HttpError as e:
            if e.resp.status == 429 and attempt < _MAX_RETRIES - 1:
                wait = _BACKOFF_BASE ** attempt
                print(f"  Sheets API rate limited. Waiting {wait}s (attempt {attempt + 1}/{_MAX_RETRIES})...")
                time.sleep(wait)
            else:
                raise


class SheetsClient:
    def __init__(self, config: dict):
        self.spreadsheet_id = config["sheets"]["spreadsheet_id"]
        self.citations_tab = config["sheets"]["citations_tab"]
        self.summary_tab = config["sheets"]["summary_tab"]

        # Auth: use explicit path from config if provided, else auto-discover
        creds_file = discover_credentials(config)
        creds = service_account.Credentials.from_service_account_file(
            creds_file, scopes=SCOPES
        )
        service = build("sheets", "v4", credentials=creds)
        self.sheet = service.spreadsheets()

    # ── Reading ────────────────────────────────────────────────────────────────

    def get_all_domains(self) -> list[dict]:
        """Load all rows from Citations tab. Returns list of dicts keyed by column name."""
        result = _execute_with_retry(self.sheet.values().get(
            spreadsheetId=self.spreadsheet_id,
            range=f"{self.citations_tab}!A2:V",
        ))
        rows = result.get("values", [])
        domains = []
        num_cols = len(HEADERS)
        for i, row in enumerate(rows):
            padded = row + [""] * (num_cols - len(row))
            entry = {key: padded[idx] for key, idx in COL.items()}
            entry["_row_index"] = i + 2  # 1-indexed, row 1 = headers
            if entry["domain"]:  # skip blank rows
                domains.append(entry)
        return domains

    def get_pending_domains(self) -> list[dict]:
        """
        Return domains that need processing.
        Skips: verified, duplicate, paid_only, manual_needed, already_listed.
        Sorted by priority ascending (1 = highest priority).
        """
        all_domains = self.get_all_domains()
        pending = [d for d in all_domains if d["status"] not in SKIP_ON_STARTUP]

        def safe_priority(d: dict) -> int:
            try:
                return int(d.get("priority") or 5)
            except (ValueError, TypeError):
                return 5

        pending.sort(key=safe_priority)
        return pending

    def get_reverify_queue(self) -> list[dict]:
        """
        Return domains due for re-verification per Phase 9 rules:
        1. pending_review / email_verification_pending / submitted with next_check_due <= today
        2. verified / verified_partial with last_checked > 30 days ago (freshness check)
        """
        today = datetime.now().date()
        thirty_days_ago = (datetime.now() - timedelta(days=30)).strftime("%Y-%m-%d")
        all_domains = self.get_all_domains()
        queue = []

        for d in all_domains:
            status = d["status"]

            # Group 1: awaiting confirmation / publication
            if status in {"pending_review", "email_verification_pending", "submitted"}:
                due = d.get("next_check_due", "")
                if not due or due <= today.strftime("%Y-%m-%d"):
                    queue.append(d)

            # Group 2: verified listings due for freshness re-check
            elif status in {"verified", "verified_partial"}:
                last = d.get("last_checked", "")
                if not last or last <= thirty_days_ago:
                    queue.append(d)

        return queue

    # ── Writing ────────────────────────────────────────────────────────────────

    def update_domain(self, row_index: int, updates: dict) -> None:
        """
        Update specific columns for a domain row.
        updates = {column_name: value}
        Uses batch update to minimize API calls.
        """
        data = []
        for col_name, value in updates.items():
            if col_name not in COL:
                print(f"  WARNING: update_domain() received unknown column '{col_name}' — skipping. Valid: {sorted(COL.keys())}")
                continue
            col_letter = _col_index_to_letter(COL[col_name])
            data.append({
                "range": f"{self.citations_tab}!{col_letter}{row_index}",
                "values": [[str(value) if value is not None else ""]],
            })

        if not data:
            return

        _execute_with_retry(self.sheet.values().batchUpdate(
            spreadsheetId=self.spreadsheet_id,
            body={"valueInputOption": "USER_ENTERED", "data": data},
        ))

    def set_status(self, row_index: int, status: str, notes: str = None) -> None:
        """Quick status update with optional notes. Validates status code."""
        if status not in STATUS_CODES:
            raise ValueError(f"Invalid status '{status}'. Valid: {sorted(STATUS_CODES)}")
        updates = {"status": status}
        if notes is not None:
            updates["notes"] = notes[:NOTE_MAX_LEN]
        self.update_domain(row_index, updates)

    def append_note(self, row_index: int, note: str) -> None:
        """Append a note to existing notes (doesn't overwrite)."""
        col_letter = _col_index_to_letter(COL["notes"])
        result = _execute_with_retry(self.sheet.values().get(
            spreadsheetId=self.spreadsheet_id,
            range=f"{self.citations_tab}!{col_letter}{row_index}",
        ))
        existing = (result.get("values", [[""]])[0] or [""])[0]
        separator = " | " if existing else ""
        new_note = (existing + separator + note)[:NOTE_MAX_LEN]
        self.update_domain(row_index, {"notes": new_note})

    def write_summary(self) -> None:
        """Recompute and write campaign summary statistics to the Summary tab."""
        all_domains = self.get_all_domains()
        status_counts: dict[str, int] = {}
        for d in all_domains:
            s = d["status"] or "not_started"
            status_counts[s] = status_counts.get(s, 0) + 1

        total = len(all_domains)
        verified = status_counts.get("verified", 0) + status_counts.get("verified_partial", 0)
        pct = round((verified / total * 100) if total > 0 else 0, 1)

        rows = [
            ["Citation Campaign Summary", ""],
            ["Last Updated", datetime.now().strftime("%Y-%m-%d %H:%M")],
            ["", ""],
            ["Total Domains", total],
            ["Verified", verified],
            ["Completion %", f"{pct}%"],
            ["", ""],
            ["Submitted (pending verification)", status_counts.get("submitted", 0)],
            ["Pending Review", status_counts.get("pending_review", 0)],
            ["Email Verification Pending", status_counts.get("email_verification_pending", 0)],
            ["", ""],
            ["Failed", status_counts.get("failed", 0)],
            ["Manual Queue", status_counts.get("manual_needed", 0) + status_counts.get("captcha_required", 0)],
            ["NAP Mismatch", status_counts.get("nap_mismatch", 0)],
            ["Needs Claim", status_counts.get("needs_claim", 0)],
            ["", ""],
            ["Paid Only (skipped)", status_counts.get("paid_only", 0)],
            ["Duplicates / Already Listed", status_counts.get("duplicate", 0) + status_counts.get("already_listed", 0)],
        ]

        _execute_with_retry(self.sheet.values().update(
            spreadsheetId=self.spreadsheet_id,
            range=f"{self.summary_tab}!A1:B{len(rows)}",
            valueInputOption="USER_ENTERED",
            body={"values": rows},
        ))

    def setup_headers(self) -> None:
        """Write column headers to row 1 of Citations tab. Run once during setup."""
        _execute_with_retry(self.sheet.values().update(
            spreadsheetId=self.spreadsheet_id,
            range=f"{self.citations_tab}!A1:V1",
            valueInputOption="USER_ENTERED",
            body={"values": [HEADERS]},
        ))
        print(f"Headers written to '{self.citations_tab}' tab ({len(HEADERS)} columns).")


def _col_index_to_letter(index: int) -> str:
    """Convert 0-based column index to spreadsheet letter (0→A, 25→Z, 26→AA)."""
    result = ""
    index += 1
    while index > 0:
        index, remainder = divmod(index - 1, 26)
        result = chr(65 + remainder) + result
    return result
