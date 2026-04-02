"""
nap_loader.py — Load and validate NAP data from nap.json.

Usage:
    from scripts.nap_loader import load_nap, get_field, get_description, get_phone

    nap = load_nap("nap.json")
    phone = get_phone(nap, format="display")
"""

import json
import re
from pathlib import Path

from scripts.shared_utils import resolve_path

REQUIRED_FIELDS = [
    "business_name", "address1", "city", "state", "state_abbr", "zip",
    "phone_display", "phone_e164", "website", "description_short", "categories_primary"
]

RECOMMENDED_FIELDS = [
    "address2", "phone_fax", "phone_sms", "email", "description_medium",
    "description_long", "categories_secondary", "keywords", "year_established",
    "payment_methods", "logo_path", "photo_paths", "social_urls", "hours",
    "tagline", "service_areas", "short_name", "owner_name", "owner_title",
    "services", "languages", "insurance_accepted", "credentials",
    "existing_profiles", "featured_message"
]


def load_nap(nap_path: str, verbose: bool = False) -> dict:
    """Load nap.json, validate required fields, and return the NAP dict."""
    path = Path(resolve_path(nap_path))
    if not path.exists():
        raise FileNotFoundError(f"nap.json not found at: {nap_path}")

    with open(path) as f:
        nap = json.load(f)

    errors = []
    warnings = []

    for field in REQUIRED_FIELDS:
        if not nap.get(field):
            errors.append(f"Missing required field: {field}")

    if nap.get("phone_e164"):
        if not re.match(r"^\+1\d{10}$", nap["phone_e164"]):
            errors.append(
                f"phone_e164 must be +1XXXXXXXXXX format (10 digits after +1), "
                f"got: {nap['phone_e164']}"
            )

    if nap.get("website") and not nap["website"].startswith("https://"):
        warnings.append(f"website should use https://, got: {nap['website']}")

    if nap.get("description_short") and len(nap["description_short"]) > 160:
        warnings.append(
            f"description_short is {len(nap['description_short'])} chars — "
            f"should be ≤160 for directory compatibility"
        )

    if verbose:
        for field in RECOMMENDED_FIELDS:
            if not nap.get(field):
                warnings.append(f"Recommended field missing: {field}")

    if errors:
        raise ValueError("NAP validation failed:\n" + "\n".join(f"  ✗ {e}" for e in errors))

    if warnings:
        print("NAP warnings (non-blocking):")
        for w in warnings:
            print(f"  ⚠  {w}")

    return nap


def get_field(nap: dict, field: str, max_length: int = None, fallback: str = "") -> str:
    """Get a NAP field with optional length truncation (truncates at word boundary)."""
    value = nap.get(field) or fallback
    if not isinstance(value, str):
        value = str(value)
    if max_length and len(value) > max_length:
        truncated = value[: max_length - 3]
        last_space = truncated.rfind(" ")
        if last_space > max_length // 2:
            truncated = truncated[:last_space]
        value = truncated + "..."
    return value


def get_description(nap: dict, max_length: int) -> str:
    """Return the longest description that fits within max_length (long → medium → short)."""
    for key in ("description_long", "description_medium", "description_short"):
        desc = nap.get(key, "")
        if desc and len(desc) <= max_length:
            return desc
    return get_field(nap, "description_short", max_length=max_length)


def get_phone(nap: dict, format: str = "display") -> str:
    """
    Return phone in requested format.
    format options: 'display' → (512) 555-1234
                    'e164'    → +15125551234
                    'digits'  → 5125551234  (10 digits, no country code)
                    'dashes'  → 512-555-1234
    """
    if format == "e164":
        return nap.get("phone_e164", "")
    elif format == "digits":
        raw = re.sub(r"\D", "", nap.get("phone_e164", ""))
        return raw[1:] if raw.startswith("1") and len(raw) == 11 else raw
    elif format == "dashes":
        digits = get_phone(nap, format="digits")
        if len(digits) == 10:
            return f"{digits[:3]}-{digits[3:6]}-{digits[6:]}"
        return digits
    else:
        return nap.get("phone_display", "")


def normalize_phone(phone: str) -> str:
    """Strip all non-digits and return last 10 digits (US number without country code)."""
    digits = re.sub(r"\D", "", phone or "")
    if len(digits) == 11 and digits.startswith("1"):
        digits = digits[1:]
    return digits[-10:] if len(digits) >= 10 else digits


def normalize_url(url: str) -> str:
    """Normalize URL for comparison: lowercase, strip scheme, www, trailing slash."""
    url = (url or "").lower().strip()
    url = re.sub(r"^https?://", "", url)
    url = re.sub(r"^www\.", "", url)
    url = url.rstrip("/")
    return url
