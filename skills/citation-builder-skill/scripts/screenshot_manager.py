"""
screenshot_manager.py — Evidence capture and organization.

Saves timestamped screenshots per domain in a structured archive under
{evidence_root}/{domain}/NN_stepname_HHMMSS.png.

The browser object must expose a screenshot() method returning bytes.
This matches the VS Code Insiders browser API.

Usage:
    from scripts.screenshot_manager import ScreenshotManager

    sm = ScreenshotManager("./evidence/")
    path = sm.capture(browser, domain="yelp.com", step="pre_submit")
    paths = sm.get_evidence_paths("yelp.com")
"""

import re
from datetime import datetime
from pathlib import Path


class ScreenshotManager:
    # Canonical step names, ordered for numbered filenames.
    STEP_ORDER = [
        "domain_intel",
        "existing_listing_check",
        "account_login",
        "account_register",
        "form_blank",
        "form_filled",
        "pre_submit",
        "confirmation",
        "email_verify",
        "live_listing",
        "error",
    ]

    def __init__(self, evidence_root: str):
        self.evidence_root = Path(evidence_root)
        self.evidence_root.mkdir(parents=True, exist_ok=True)

    def domain_dir(self, domain: str) -> Path:
        """Get (or create) the evidence directory for a domain."""
        safe = re.sub(r"[^\w\-.]", "_", domain)
        d = self.evidence_root / safe
        d.mkdir(parents=True, exist_ok=True)
        return d

    def screenshot_path(self, domain: str, step: str) -> str:
        """
        Return the full path for a screenshot file.
        Files are named: NN_stepname_HHMMSS.png where NN is the step order number.
        Unknown steps get prefix 99.
        """
        step_num = (self.STEP_ORDER.index(step) + 1) if step in self.STEP_ORDER else 99
        timestamp = datetime.now().strftime("%H%M%S")
        filename = f"{step_num:02d}_{step}_{timestamp}.png"
        return str(self.domain_dir(domain) / filename)

    def capture(self, browser, domain: str, step: str) -> tuple[str, bool]:
        """
        Capture a screenshot via the browser object and save to the evidence archive.
        Returns (path, success). Path is always set (useful for logging even on failure).
        """
        path = self.screenshot_path(domain, step)
        try:
            screenshot_bytes = browser.screenshot()
            Path(path).write_bytes(screenshot_bytes)
            print(f"  📷 {step}: {path}")
            return path, True
        except Exception as e:
            print(f"  ⚠  Screenshot failed ({step}): {e}")
            return path, False

    def get_evidence_paths(self, domain: str) -> list[str]:
        """List all screenshots for a domain, sorted by filename."""
        return sorted(str(p) for p in self.domain_dir(domain).glob("*.png"))
