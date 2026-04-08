"""
preflight.py — Pre-flight validation. Run before any campaign.

Usage:
    python -m scripts.preflight --config config.json
    # or
    from scripts.preflight import run_preflight
    ok = run_preflight("config.json")
"""

import argparse
import os
import sys
from pathlib import Path

from scripts.nap_loader import load_nap
from scripts.sheets_client import SheetsClient
from scripts.shared_utils import discover_credentials, ensure_env, load_config, resolve_path, validate_config
from scripts.credential_vault import validate_vault_key


def run_preflight(config_path: str) -> bool:
    """
    Run all pre-flight checks. Prints results.
    Returns True if all required checks pass, False otherwise.
    """
    ensure_env()

    print("=" * 50)
    print("Pre-flight Validation")
    print("=" * 50)

    config = load_config(config_path)

    errors = []
    warnings = []

    # 0. Config structure validation
    try:
        validate_config(config)
        print("  \u2713 Config structure valid (all required keys present)")
    except ValueError as e:
        errors.append(str(e))

    # 1. nap.json validation
    try:
        load_nap(config["nap_path"], verbose=True)
        print("  ✓ nap.json valid and complete")
    except FileNotFoundError as e:
        errors.append(f"nap.json not found: {e}")
    except ValueError as e:
        errors.append(f"nap.json invalid: {e}")

    # 2. Google credentials discovery
    try:
        creds_file = discover_credentials(config)
        print(f"  ✓ Credentials: {creds_file}")
    except (FileNotFoundError, RuntimeError) as e:
        errors.append(str(e))

    # 3. Credential vault key
    try:
        validate_vault_key()
        print("  ✓ CITATION_VAULT_KEY configured")
    except (EnvironmentError, ValueError) as e:
        errors.append(str(e))

    # 4. Google Sheets connectivity
    spreadsheet_id = config.get("sheets", {}).get("spreadsheet_id", "")
    if not spreadsheet_id or spreadsheet_id == "YOUR_SPREADSHEET_ID_HERE":
        errors.append(
            "sheets.spreadsheet_id is missing or still has placeholder value.\n"
            "  Set CITATION_SPREADSHEET_ID in secrets/.env.agent or update config.json."
        )
    else:
        try:
            client = SheetsClient(config)
            domains = client.get_all_domains()
            print(f"  \u2713 Google Sheets connected ({len(domains)} domains loaded)")
        except Exception as e:
            errors.append(f"Google Sheets connection failed: {e}")

    # 5. Email configuration
    email_cfg = config.get("email", {})
    if email_cfg.get("use_gmail_api"):
        if not email_cfg.get("gmail_subject_user"):
            errors.append(
                "email.use_gmail_api=true but gmail_subject_user not set in config. "
                "See references/setup.md → Gmail API section."
            )
        else:
            print(f"  ✓ Gmail API configured (subject: {email_cfg['gmail_subject_user']})")
    else:
        missing = [v for v in ("CITATION_EMAIL", "CITATION_EMAIL_PASSWORD")
                   if not os.environ.get(v)]
        if missing:
            errors.append(f"IMAP env vars not set: {missing} (required for email verification)")
        else:
            imap_host = os.environ.get("CITATION_IMAP_HOST", "imap.gmail.com")
            print(f"  \u2713 IMAP email configured ({os.environ['CITATION_EMAIL']} via {imap_host})")

    # 6. Evidence directory (create if missing)
    evidence_path = resolve_path(config.get("evidence_path", "./evidence/"))
    Path(evidence_path).mkdir(parents=True, exist_ok=True)
    print(f"  ✓ Evidence directory ready: {evidence_path}")

    # Summary
    print()
    if warnings:
        print("Warnings:")
        for w in warnings:
            print(f"  ⚠  {w}")
        print()

    if errors:
        print("ERRORS (must fix before running campaign):")
        for e in errors:
            print(f"  ✗ {e}")
        print()
        print("Pre-flight FAILED.")
        return False

    print("Pre-flight PASSED. Ready to run campaign.")
    return True


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run citation campaign pre-flight checks")
    parser.add_argument("--config", default="config.json")
    args = parser.parse_args()
    ok = run_preflight(args.config)
    sys.exit(0 if ok else 1)
