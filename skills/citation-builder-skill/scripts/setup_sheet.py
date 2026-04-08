"""
setup_sheet.py — One-time Google Sheet initialization.

Creates column headers on the Citations tab and initializes the Summary tab.
Run this once before adding domain data or starting a campaign.

Usage:
    python -m scripts.setup_sheet --config config.json
"""

import argparse

from scripts.sheets_client import SheetsClient
from scripts.shared_utils import ensure_env, load_config, validate_config


def setup_sheet(config_path: str) -> None:
    ensure_env()
    config = load_config(config_path)
    validate_config(config)

    client = SheetsClient(config)

    print("Writing headers to Citations tab...")
    client.setup_headers()

    print("Initializing Summary tab...")
    client.write_summary()

    spreadsheet_id = config["sheets"]["spreadsheet_id"]
    print(f"\nSheet setup complete.")
    print(f"Spreadsheet ID: {spreadsheet_id}")
    print(f"Open: https://docs.google.com/spreadsheets/d/{spreadsheet_id}/edit")
    print(f"\nNext: add your citation domains to column A (Citations tab), one per row starting at row 2.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Initialize Google Sheet for citation campaign")
    parser.add_argument("--config", default="config.json", help="Path to config.json")
    args = parser.parse_args()
    setup_sheet(args.config)
