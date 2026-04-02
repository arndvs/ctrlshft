"""
run_campaign.py — Main campaign orchestrator.

Runs Phases 0-8 per domain, updates Google Sheet after each phase,
handles errors with circuit breaker logic.

Auth: Follows google-docs.instructions.md — service account from ~/dotfiles/secrets/.
Venv must be active: source ~/dotfiles/secrets/.venv/bin/activate

Usage:
    python -m scripts.run_campaign --config config.json
    python -m scripts.run_campaign --config config.json --domain yelp.com
    python -m scripts.run_campaign --config config.json --dry-run
    python -m scripts.run_campaign --config config.json --preflight-only
"""

import argparse
import json
import sys
import time
from datetime import datetime

from scripts.preflight import run_preflight
from scripts.nap_loader import load_nap, normalize_phone
from scripts.shared_utils import due_date, NOTE_MAX_LEN, CircuitBreaker, resolve_path, load_config, validate_config, ensure_env
from scripts.sheets_client import SheetsClient
from scripts.credential_vault import get_credentials, store_credentials
from scripts.email_handler import EmailHandler
from scripts.listing_qa import ListingQA
from scripts.screenshot_manager import ScreenshotManager
from scripts.session_logger import SessionLogger


class CitationCampaignRunner:
    """
    Orchestrates the full citation building pipeline.

    Each domain goes through Phases 1-8. The Google Sheet is updated
    after every phase so the run is fully resumable.

    The 'browser' attribute must be set to the VS Code Insiders browser
    object before calling run(). The agent injects this dependency.
    """

    def __init__(self, config_path: str):
        ensure_env()

        self.config_path = config_path
        self.config      = load_config(config_path)
        validate_config(self.config)

        self.nap = load_nap(self.config["nap_path"])
        self.sheets = SheetsClient(self.config)
        self.email_handler = EmailHandler(self.config)
        self.qa = ListingQA(self.nap)
        self.screenshots = ScreenshotManager(resolve_path(self.config["evidence_path"]))
        self.logger = SessionLogger(resolve_path(self.config["evidence_path"]))
        self.vault_path = resolve_path(self.config["credentials_path"])

        self.browser = None

        self.submissions_this_session = 0
        self.max_submissions          = self.config["session"]["max_submissions_per_session"]
        self.breaker                  = CircuitBreaker(self.config["session"]["circuit_breaker_threshold"])
        self.domain_cooldown          = self.config["session"]["domain_cooldown_seconds"]

    def run(self, dry_run: bool = False, single_domain: str = None) -> None:
        """Run campaign. Optionally limited to a single domain or dry-run mode."""
        if self.browser is None and not dry_run:
            raise RuntimeError(
                "browser not injected — agent must set runner.browser before calling run()"
            )

        if not run_preflight(self.config_path):
            print("\nPre-flight failed. Fix errors above before running campaign.")
            sys.exit(1)

        print(f"\n{'=' * 55}")
        print(f"Citation Campaign  |  Session {self.logger.session_id}")
        print(f"Mode: {'DRY RUN' if dry_run else 'LIVE'}")
        print(f"{'=' * 55}\n")

        pending = self.sheets.get_pending_domains()

        if single_domain:
            pending = [d for d in pending if d["domain"] == single_domain]
            if not pending:
                print(f"Domain '{single_domain}' not found in pending queue.")
                return

        print(f"Pending domains: {len(pending)}")
        if not dry_run:
            print(f"Session limit: {self.max_submissions} submissions\n")

        try:
            for domain_row in pending:
                if self.submissions_this_session >= self.max_submissions and not dry_run:
                    print(f"\nSession limit reached ({self.max_submissions}). Stopping.")
                    break

                self._run_domain(domain_row, dry_run=dry_run)

                if self.breaker.tripped:
                    print(f"\n⛔ CIRCUIT BREAKER: {self.breaker.consecutive_failures} consecutive failures.")
                    print("Likely causes: IP block, credential issue, browser crash, Sheets API error.")
                    print("Check session log and resolve before restarting.")
                    break

                if not dry_run:
                    print(f"  Cooling down {self.domain_cooldown}s before next domain...")
                    time.sleep(self.domain_cooldown)
        finally:
            self.sheets.write_summary()
            self.logger.close()

        print(f"\nCampaign session complete. {self.submissions_this_session} submissions made.")

    def _run_domain(self, domain_row: dict, dry_run: bool = False) -> None:
        domain = domain_row["domain"]
        row_index = domain_row["_row_index"]
        print(f"\n{'─' * 50}")
        print(f"Domain: {domain}  (row {row_index})")

        self.nap = load_nap(self.config["nap_path"])
        self.qa  = ListingQA(self.nap)

        if not dry_run:
            self.sheets.set_status(row_index, "in_progress")
        self.logger.log_event(domain, "phase_start", {"dry_run": dry_run})

        # ── Phases 1-4: Pre-submission (safe to retry on failure) ─────────────
        try:
            # ── Phase 1: Domain Intelligence ──────────────────────────────────
            print(f"  [Phase 1] Domain intelligence...")
            intel = self._phase1_intel(domain, row_index)
            if intel.get("skip"):
                self.breaker.reset()
                return

            # ── Phase 2: Account Management ───────────────────────────────────
            print(f"  [Phase 2] Account management...")
            account = self._phase2_account(domain, row_index, intel)
            if account.get("skip"):
                return

            # ── Phase 3: Duplicate Detection ──────────────────────────────────
            print(f"  [Phase 3] Duplicate detection...")
            dup = self._phase3_duplicate_check(domain, row_index, intel)
            if dup.get("skip"):
                self.breaker.reset()
                return

            # ── Phase 4: NAP Field Mapping ────────────────────────────────────
            print(f"  [Phase 4] NAP field mapping...")
            field_map = self._phase4_nap_mapping(domain, intel)

            if dry_run:
                print(f"  [DRY RUN] Would submit {len(field_map)} mapped fields to {intel['submission_url']}")
                self.logger.log_event(domain, "dry_run_complete", {"field_count": len(field_map)})
                return

        except Exception as e:
            self.breaker.record_failure()
            print(f"  ERROR (pre-submission): {e}")
            self.sheets.set_status(row_index, "failed", f"{type(e).__name__}: {str(e)[:NOTE_MAX_LEN]}")
            self.logger.log_error(domain, e)
            return

        # ── Phase 5: Submission ───────────────────────────────────────────────
        try:
            print(f"  [Phase 5] Submitting...")
            submission = self._phase5_submit(domain, row_index, field_map, intel)

            if not submission.get("success"):
                self.breaker.record_failure()
                return

            self.submissions_this_session += 1
            self.breaker.reset()

        except Exception as e:
            self.breaker.record_failure()
            print(f"  ERROR (submission): {e}")
            self.sheets.set_status(row_index, "failed", f"{type(e).__name__}: {str(e)[:NOTE_MAX_LEN]}")
            self.logger.log_error(domain, e)
            return

        # ── Phases 6-7: Post-submission (never revert to "failed") ────────────
        try:
            # ── Phase 6: Email Verification ───────────────────────────────────
            if submission.get("needs_email_verify"):
                print(f"  [Phase 6] Awaiting email verification...")
                self._phase6_email_verify(domain, row_index, intel, submission)

            # ── Phase 7: Live Listing QA ──────────────────────────────────────
            listing_url = submission.get("listing_url") or domain_row.get("listing_url")

            if listing_url:
                print(f"  [Phase 7] QA check on live listing...")
                self._phase7_qa(domain, row_index, listing_url)
            else:
                self.sheets.update_domain(row_index, {
                    "status": "pending_review",
                    "next_check_due": due_date(3),
                })
                print(f"  [Phase 7] Listing not yet live. Scheduled re-check: {due_date(3)}")

            self.logger.log_event(domain, "phase_complete", {"status": "submitted"})

        except Exception as e:
            print(f"  ERROR (post-submission): {e}")
            self.sheets.append_note(row_index, f"Post-submit error: {type(e).__name__}: {str(e)[:NOTE_MAX_LEN]}")
            self.sheets.update_domain(row_index, {"next_check_due": due_date(1)})
            self.logger.log_error(domain, e)

    # ── Phase implementations ──────────────────────────────────────────────────

    def _phase1_intel(self, domain: str, row_index: int) -> dict:
        """
        Research domain before submission.
        Agent: use browser to discover submission URL, platform type,
        check for existing listing, detect CAPTCHA and paid gates.
        """
        # Agent navigates to domain and inspects it via browser here.
        # The agent should populate this dict based on what it finds.
        intel = {
            "submission_url": None,    # agent discovers this
            "platform_type": "generic",
            "captcha_type": "none",
            "cost_gate": False,
            "existing_listing": None,  # dict with url/nap if found, else None
            "skip": False,
        }

        # Update Sheet with discovered intel
        updates = {
            "platform_type": intel["platform_type"],
            "captcha_type": intel["captcha_type"],
            "cost_gate": "TRUE" if intel["cost_gate"] else "FALSE",
        }
        if intel.get("submission_url"):
            updates["submission_url"] = intel["submission_url"]

        # Auto-skip: paid only
        if intel["cost_gate"]:
            self.sheets.update_domain(row_index, {**updates, "status": "paid_only"})
            print(f"  → Skipping: paid listing only")
            intel["skip"] = True
            return intel

        # Auto-skip: listing already exists with matching NAP
        if intel["existing_listing"]:
            self.sheets.update_domain(row_index, {
                **updates,
                "status": "already_listed",
                "listing_url": intel["existing_listing"].get("url", ""),
                "notes": "Existing listing found with matching NAP",
            })
            print(f"  → Skipping: already listed at {intel['existing_listing'].get('url')}")
            intel["skip"] = True
            return intel

        self.sheets.update_domain(row_index, updates)
        return intel

    def _phase2_account(self, domain: str, row_index: int, intel: dict) -> dict:
        """
        Ensure a valid account exists and is logged in.
        Agent: check vault, attempt login, register if needed.
        """
        creds = get_credentials(self.vault_path, domain)

        if creds:
            # Agent: attempt login with creds["email"] and creds["password"]
            # logged_in = agent_attempt_login(domain, creds, self.browser)
            logged_in = True  # agent determines this

            if not logged_in:
                # Try to recover — agent attempts password reset
                self.sheets.append_note(row_index, "Login failed — attempting recovery")
                # If recovery fails, flag for manual
                self.sheets.set_status(row_index, "manual_needed", "Login failed and recovery unsuccessful")
                return {"skip": True}

            self.sheets.update_domain(row_index, {
                "email_used": creds["email"],
                "username": creds.get("username", ""),
            })
        else:
            # Register new account
            # Agent determines email strategy: alias for most, business email for priority dirs
            high_priority_domains = {"yelp.com", "bbb.org", "yellowpages.com"}
            if domain in high_priority_domains:
                reg_email = self.config["email"].get("business_email") or self.config["email"].get("verification_account")
                if not reg_email:
                    raise ValueError(
                        "No business_email or verification_account in config. "
                        "Set CITATION_BUSINESS_EMAIL or CITATION_VERIFICATION_EMAIL in secrets/.env."
                    )
            else:
                verification_email = self.config["email"].get("verification_account", "")
                if not verification_email or "@" not in verification_email:
                    raise ValueError(f"Invalid verification_account in config (missing @): {verification_email}")
                local, domain_part = verification_email.split("@", 1)
                slug = domain.replace(".", "_").replace("-", "_")
                reg_email = f"{local}+{slug}@{domain_part}"

            # Agent: register account on the directory with reg_email
            # password = agent_generate_and_register(domain, reg_email, self.browser)
            password = None  # agent sets this

            if password:
                store_credentials(self.vault_path, domain, reg_email, password)
                self.sheets.update_domain(row_index, {"email_used": reg_email})
            else:
                self.sheets.set_status(row_index, "manual_needed", "Account registration failed")
                return {"skip": True}

        return {"skip": False}

    def _phase3_duplicate_check(self, domain: str, row_index: int, intel: dict) -> dict:
        """
        Search directory for existing listing.
        Agent: use browser to search by name, phone, and URL.
        """
        # Agent searches directory here
        # result = agent_search_directory(domain, self.nap, self.browser)
        # result = {"found": False} | {"found": True, "url": "...", "nap": {...}}
        result = {"found": False}  # agent populates

        if result["found"]:
            found_url = result.get("url", "")
            found_nap = result.get("nap", {})

            # Quick NAP check — does name and phone match?
            name_match = self.nap["business_name"].lower() in (found_nap.get("name") or "").lower()
            canonical_phone = normalize_phone(self.nap["phone_e164"])
            found_phone     = normalize_phone(found_nap.get("phone") or "")
            phone_match     = canonical_phone and canonical_phone == found_phone

            if name_match and phone_match:
                self.sheets.update_domain(row_index, {
                    "status": "already_listed",
                    "listing_url": found_url,
                    "notes": "Existing listing found with matching NAP — skipped",
                })
                print(f"  → Already listed: {found_url}")
                return {"skip": True}
            else:
                self.sheets.update_domain(row_index, {
                    "status": "needs_claim",
                    "listing_url": found_url,
                    "notes": f"Listing exists with conflicting NAP — needs claim/correction",
                })
                print(f"  → Conflicting listing found: {found_url} — flagged for claim")
                return {"skip": True}

        return {"skip": False}

    def _phase4_nap_mapping(self, domain: str, intel: dict) -> dict:
        """
        Map canonical NAP fields to this directory's form field selectors.
        Returns dict: {css_selector_or_field_name: value_to_fill}
        Agent loads platform adapter from references/platform_adapters.md.
        """
        # Agent builds this mapping based on the platform adapter and live form inspection
        field_map = {}
        return field_map

    def _phase5_submit(self, domain: str, row_index: int, field_map: dict, intel: dict) -> dict:
        """
        Execute form submission via browser.
        Agent: navigate to submission URL, fill each field, submit.
        Returns {"success": bool, "needs_email_verify": bool, "listing_url": str|None,
                 "confirmation_id": str|None}
        """
        submission_url = intel.get("submission_url")
        if not submission_url:
            self.sheets.set_status(row_index, "failed", "Phase 1 did not discover a submission URL")
            return {
                "success": False,
                "error": "No submission URL discovered in Phase 1",
            }

        # Agent: capture screenshots at each step using self.screenshots.capture()
        # pre_path  = self.screenshots.capture(self.browser, domain, "form_blank")
        # ... fill form fields ...
        # self.screenshots.capture(self.browser, domain, "form_filled")
        # ... click submit ...
        # conf_path = self.screenshots.capture(self.browser, domain, "confirmation")

        # Agent populates result:
        # AGENT: set result["success"] = True after successful form submission
        # AGENT: set result["evidence_path"] to the evidence dir for this domain
        evidence_dir = str(self.screenshots.domain_dir(domain))
        result = {
            "success": False,
            "needs_email_verify": False,
            "listing_url": None,
            "confirmation_id": None,
            "evidence_path": evidence_dir,
            "submitted_at": datetime.now(),
        }

        if result["success"]:
            self.sheets.update_domain(row_index, {
                "status": "submitted",
                "date_submitted": datetime.now().strftime("%Y-%m-%d %H:%M"),
                "confirmation_id": result.get("confirmation_id") or "",
                "listing_url": result.get("listing_url") or "",
                "evidence_path": result.get("evidence_path") or "",
                "verification_method": "email" if result["needs_email_verify"] else "auto",
            })
            print(f"  ✓ Submitted. Confirmation: {result.get('confirmation_id')}")
        else:
            self.sheets.set_status(row_index, "failed", result.get("error", "Submission failed"))

        return result

    def _phase6_email_verify(self, domain: str, row_index: int, intel: dict, submission: dict) -> None:
        """Wait for verification email, then navigate browser to the verification link."""
        submitted_at = submission.get("submitted_at") or datetime.now()
        self.sheets.set_status(row_index, "email_verification_pending")

        url = self.email_handler.wait_for_verification_email(domain, submitted_after=submitted_at)

        if url:
            # Agent: navigate browser to verification URL and confirm success
            # self.browser.navigate(url)
            # self.screenshots.capture(self.browser, domain, "email_verify")
            # Agent should check the resulting page for success/error messaging
            # before treating verification as complete.

            self.sheets.update_domain(row_index, {
                "status": "pending_review",
                "date_verified": datetime.now().strftime("%Y-%m-%d %H:%M"),
                "verification_method": "email",
                "notes": f"Email verification link visited: {url[:200]}",
            })
            print(f"  ✓ Email verification link clicked")
        else:
            self.sheets.update_domain(row_index, {
                "next_check_due": due_date(1),
                "notes": "Email verification pending — will recheck in 24h",
            })
            print(f"  ⏳ Email verification pending (scheduled recheck: {due_date(1)})")

    def _phase7_qa(self, domain: str, row_index: int, listing_url: str) -> None:
        """Scrape live listing and score NAP accuracy."""
        # Agent: navigate to listing_url, scrape NAP fields
        # scraped_nap = agent_scrape_nap(listing_url, self.browser)
        scraped_nap = {}  # agent populates: {name, phone, address, website}

        if not scraped_nap:
            self.sheets.update_domain(row_index, {
                "status": "pending_review",
                "notes": "Listing URL loaded but no NAP scraped — check manually",
                "next_check_due": due_date(3),
            })
            return

        result = self.qa.score_listing(listing_url, scraped_nap)
        # Agent: capture screenshot of live listing
        # self.screenshots.capture(self.browser, domain, "live_listing")
        evidence_dir = str(self.screenshots.domain_dir(domain))

        self.sheets.update_domain(row_index, {
            "status": result["status"],
            "nap_match_score": result["score"],
            "last_checked": due_date(0),
            "next_check_due": due_date(30),
            "notes": "; ".join(result["discrepancies"]) if result["discrepancies"] else "NAP verified ✓",
            "evidence_path": evidence_dir,
        })

        print(f"  NAP score: {result['score']}/100 → {result['status']}")
        if result["discrepancies"]:
            for d in result["discrepancies"]:
                print(f"    ⚠  {d}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Automated citation building campaign")
    parser.add_argument("--config", default="config.json", help="Path to config.json")
    parser.add_argument("--domain", help="Process a single domain only")
    parser.add_argument("--dry-run", action="store_true", help="Simulate without submitting")
    parser.add_argument("--preflight-only", action="store_true", help="Only run pre-flight checks")
    args = parser.parse_args()

    if args.preflight_only:
        ok = run_preflight(args.config)
        sys.exit(0 if ok else 1)

    runner = CitationCampaignRunner(args.config)
    runner.run(dry_run=args.dry_run, single_domain=args.domain)
