"""
listing_qa.py — Scrape a live directory listing and score NAP accuracy.

Usage:
    from scripts.listing_qa import ListingQA
    qa = ListingQA(nap)
    result = qa.score_listing(listing_url="https://yelp.com/biz/acme-plumbing", scraped_nap={...})
    print(result["score"], result["status"], result["discrepancies"])
"""

import re
from scripts.nap_loader import normalize_phone, normalize_url


class ListingQA:
    """
    Score a scraped NAP dict against the canonical nap.json.

    Score breakdown (100 pts total):
        Business name : 30 pts
        Phone number  : 25 pts
        Address       : 25 pts
        Website URL   : 20 pts
    """

    # Thresholds
    VERIFIED_THRESHOLD = 90
    PARTIAL_THRESHOLD = 70

    def __init__(self, nap: dict):
        self.nap = nap

    def score_listing(self, listing_url: str, scraped_nap: dict) -> dict:
        """
        Compare scraped NAP against canonical NAP.

        Args:
            listing_url: The live URL that was scraped (for logging).
            scraped_nap: Dict with keys: name, phone, address, website.
                         Any key may be None / missing.

        Returns:
            {
                "score": int (0-100),
                "status": "verified" | "verified_partial" | "nap_mismatch",
                "details": {"name": int, "phone": int, "address": int, "website": int},
                "discrepancies": [str, ...]
            }
        """
        score = 0
        details = {}
        discrepancies = []

        # ── Name (30 pts) ──────────────────────────────────────────────────────
        canonical_name = self.nap["business_name"].lower().strip()
        scraped_name = (scraped_nap.get("name") or "").lower().strip()

        if canonical_name and scraped_name:
            if canonical_name == scraped_name:
                details["name"] = 30
                score += 30
            elif canonical_name in scraped_name or scraped_name in canonical_name:
                details["name"] = 20
                score += 20
                discrepancies.append(
                    f"name partial match: listed='{scraped_nap.get('name')}' "
                    f"canonical='{self.nap['business_name']}'"
                )
            else:
                details["name"] = 0
                discrepancies.append(
                    f"name MISMATCH: listed='{scraped_nap.get('name')}' "
                    f"canonical='{self.nap['business_name']}'"
                )
        else:
            details["name"] = 0
            if not scraped_name:
                discrepancies.append("name: not found on listing page")

        # ── Phone (25 pts) ─────────────────────────────────────────────────────
        canonical_phone = normalize_phone(self.nap.get("phone_e164", ""))
        scraped_phone = normalize_phone(scraped_nap.get("phone") or "")

        if canonical_phone and scraped_phone:
            if canonical_phone == scraped_phone:
                details["phone"] = 25
                score += 25
            else:
                details["phone"] = 0
                discrepancies.append(
                    f"phone MISMATCH: listed='{scraped_nap.get('phone')}' "
                    f"canonical='{self.nap['phone_display']}'"
                )
        else:
            details["phone"] = 0
            if not scraped_phone:
                discrepancies.append("phone: not found on listing page")

        # ── Address (25 pts) ───────────────────────────────────────────────────
        canonical_addr = _normalize_address(
            f"{self.nap['address1']} {self.nap.get('address2', '')} "
            f"{self.nap['city']} {self.nap['state_abbr']} {self.nap['zip']}"
        )
        scraped_addr = _normalize_address(scraped_nap.get("address") or "")

        if canonical_addr and scraped_addr:
            if canonical_addr == scraped_addr:
                details["address"] = 25
                score += 25
            elif (
                self.nap["zip"].split("-")[0] in scraped_addr
                and self.nap["city"].lower() in scraped_addr
            ):
                # City and zip match — close enough for partial credit
                details["address"] = 15
                score += 15
                discrepancies.append(
                    f"address partial: listed='{scraped_nap.get('address')}' "
                    f"canonical='{self.nap['address1']}, {self.nap['city']}, "
                    f"{self.nap['state_abbr']} {self.nap['zip']}'"
                )
            else:
                details["address"] = 0
                discrepancies.append(
                    f"address MISMATCH: listed='{scraped_nap.get('address')}' "
                    f"canonical='{self.nap['address1']}, {self.nap['city']}, "
                    f"{self.nap['state_abbr']} {self.nap['zip']}'"
                )
        else:
            details["address"] = 0
            if not scraped_addr:
                discrepancies.append("address: not found on listing page")

        # ── Website (20 pts) ───────────────────────────────────────────────────
        canonical_url = normalize_url(self.nap.get("website", ""))
        scraped_url = normalize_url(scraped_nap.get("website") or "")

        if canonical_url and scraped_url:
            if canonical_url == scraped_url:
                details["website"] = 20
                score += 20
            else:
                details["website"] = 0
                discrepancies.append(
                    f"website MISMATCH: listed='{scraped_nap.get('website')}' "
                    f"canonical='{self.nap['website']}'"
                )
        else:
            details["website"] = 0
            if scraped_nap.get("website") is not None and not scraped_url:
                discrepancies.append("website: not found on listing page")

        # ── Status ─────────────────────────────────────────────────────────────
        if score >= self.VERIFIED_THRESHOLD:
            status = "verified"
        elif score >= self.PARTIAL_THRESHOLD:
            status = "verified_partial"
        else:
            status = "nap_mismatch"

        return {
            "score": score,
            "status": status,
            "details": details,
            "discrepancies": discrepancies,
            "listing_url": listing_url,
        }


def _normalize_address(addr: str) -> str:
    """
    Normalize address for comparison:
    - Lowercase
    - Contract full words to abbreviations (canonical NAP uses abbreviated forms)
    - Strip extra whitespace and periods
    """
    addr = (addr or "").lower().strip()
    addr = addr.replace(".", "")
    addr = re.sub(r"\s+", " ", addr)

    contractions = {
        r"\bstreet\b": "st",
        r"\bavenue\b": "ave",
        r"\bboulevard\b": "blvd",
        r"\bdrive\b": "dr",
        r"\broad\b": "rd",
        r"\blane\b": "ln",
        r"\bcourt\b": "ct",
        r"\bplace\b": "pl",
        r"\bsuite\b": "ste",
        r"\bapartment\b": "apt",
    }
    for pattern, replacement in contractions.items():
        addr = re.sub(pattern, replacement, addr)

    return re.sub(r"\s+", " ", addr).strip()
