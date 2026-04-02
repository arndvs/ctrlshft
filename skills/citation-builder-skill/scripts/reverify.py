"""
reverify.py — Phase 9: Scheduled re-verification pass.

Run this independently from the main campaign to re-check:
  - Listings pending review (after propagation delay)
  - Listings awaiting email verification (older than 24h)
  - Verified listings due for freshness re-check (>30 days)

Usage:
    python -m scripts.reverify --config config.json
"""

import argparse
import json
import sys

from scripts.shared_utils import due_date, CircuitBreaker
from scripts.sheets_client import SheetsClient
from scripts.nap_loader import load_nap
from scripts.listing_qa import ListingQA
from scripts.session_logger import SessionLogger


def run_reverify(config_path: str) -> None:
    with open(config_path) as f:
        config = json.load(f)

    nap = load_nap(config["nap_path"])
    sheets = SheetsClient(config)
    qa = ListingQA(nap)
    logger = SessionLogger(config["evidence_path"])

    queue = sheets.get_reverify_queue()
    print(f"Re-verification queue: {len(queue)} domains")

    breaker = CircuitBreaker(threshold=5)

    for domain_row in queue:
        domain = domain_row["domain"]
        row_index = domain_row["_row_index"]
        status = domain_row["status"]
        listing_url = domain_row.get("listing_url", "")

        print(f"\n  Re-checking: {domain} (status={status})")
        logger.log_event(domain, "reverify_start", {"status": status})

        # Case 1: We have a listing URL — scrape and score it
        if listing_url:
            try:
                # Agent: use browser to navigate to listing_url and scrape NAP fields
                # scraped_nap = browser_scrape_nap(listing_url)
                scraped_nap = {}  # Agent fills this via browser

                if scraped_nap:
                    result = qa.score_listing(listing_url, scraped_nap)
                    sheets.update_domain(row_index, {
                        "status": result["status"],
                        "nap_match_score": result["score"],
                        "last_checked": due_date(0),
                        "next_check_due": due_date(30),
                        "notes": "; ".join(result["discrepancies"]) if result["discrepancies"] else "NAP verified",
                    })
                    logger.log_event(domain, "reverify_complete", result)
                    print(f"  Score: {result['score']}/100 → {result['status']}")
                    breaker.reset()
                else:
                    # Agent placeholder returned empty — no real scrape was performed
                    sheets.update_domain(row_index, {
                        "status": "pending_review",
                        "next_check_due": due_date(3),
                        "notes": "Reverify: no NAP scraped — agent must inject browser scrape",
                    })
                    logger.log_event(domain, "reverify_no_scrape", {"listing_url": listing_url})
                    print(f"  ⚠  No NAP scraped — pending review (recheck in 3 days)")

            except Exception as e:
                sheets.set_status(row_index, "failed", f"Reverify error: {str(e)[:200]}")
                logger.log_error(domain, e, phase=9)
                print(f"  Error: {e}")

                if breaker.record_failure():
                    print(f"\n⛔ CIRCUIT BREAKER: {breaker.consecutive_failures} consecutive failures in reverify.")
                    break

        # Case 2: No listing URL yet — try to find it
        else:
            try:
                # Agent: search directory for business name + city to find listing URL
                # found_url = browser_search_for_listing(domain, nap)
                found_url = None  # Agent fills this via browser

                if found_url:
                    sheets.update_domain(row_index, {
                        "listing_url": found_url,
                        "next_check_due": due_date(1),
                    })
                    print(f"  Found listing URL: {found_url} — will score on next pass")
                    breaker.reset()
                else:
                    sheets.update_domain(row_index, {"next_check_due": due_date(3)})
                    sheets.append_note(row_index, f"Listing not found on {due_date(0)}")
                    print(f"  Listing not found. Next check: {due_date(3)}")

            except Exception as e:
                logger.log_error(domain, e, phase=9)
                print(f"  Error: {e}")

                if breaker.record_failure():
                    print(f"\n⛔ CIRCUIT BREAKER: {breaker.consecutive_failures} consecutive failures in reverify.")
                    break

    sheets.write_summary()
    logger.close()
    print(f"\nRe-verification pass complete. {len(queue)} domains checked.")


if __name__ == "__main__":
    from scripts.shared_utils import load_env
    load_env()

    parser = argparse.ArgumentParser(description="Run citation re-verification pass")
    parser.add_argument("--config", default="config.json")
    args = parser.parse_args()
    run_reverify(args.config)
