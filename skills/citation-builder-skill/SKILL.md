---
name: citation-builder
description: > Fully automated local SEO citation building agent. Use this skill whenever the user wants to submit business listings to citation directories, build local SEO citations at scale, automate NAP submissions, manage directory listings, track citation status, or verify submitted listings. Triggers on: "build citations", "submit to directories", "citation campaign", "local SEO listings", "directory submissions", "NAP consistency", "citation audit", "automate directory submissions". This skill covers the complete pipeline from domain list ingestion through submission, email verification, live listing QA, and Google Sheets status tracking.
---

# Automated SEO Citation Building

A complete agentic pipeline for submitting business NAP data to citation directories. Uses VS Code Insiders browser for form automation, Google Sheets API for state management, an email account for verification emails, and a local `nap.json` as the single canonical NAP source.

---

## First-Time Setup

Before running any campaign:

```bash
# 1. Activate the shared venv (per google-docs.instructions.md)
source ~/dotfiles/secrets/.venv/bin/activate

# 2. Install additional dependencies
pip install cryptography

# 3. Generate vault key (copy output, keep secure — never store in config.json)
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
export CITATION_VAULT_KEY="paste-key-here"

# 4. Copy and fill in your NAP data
cp assets/nap_template.json nap.json
# Edit nap.json — all required fields must be filled

# 5. Edit config.json — set your spreadsheet ID and email settings

# 6. Initialize the credential vault
python -c "from scripts.credential_vault import init_vault; init_vault('credentials.vault')"

# 7. Set up Google Sheet headers (run from project root)
python -m scripts.setup_sheet --config config.json

# 8. Run pre-flight check
python -m scripts.preflight --config config.json
```

See `references/setup.md` for full Google credentials setup and Gmail API delegation.

---

## Actual File Structure

```
citation-builder-skill/
├── SKILL.md                          ← this file
├── config.json                       ← you create this (see template below)
├── nap.json                          ← you create this from assets/nap_template.json
├── credentials.vault                 ← auto-created by init_vault()
├── assets/
│   └── nap_template.json             ← copy and fill in
├── references/
│   ├── setup.md                      ← Google auth, Gmail API, first-run checklist
│   ├── platform_adapters.md          ← per-directory field mappings and quirks
│   └── troubleshooting.md            ← common errors and fixes
└── scripts/
    ├── __init__.py                   ← makes scripts/ a package (required)
    ├── shared_utils.py               ← discover_credentials() and due_date() shared by all modules
    ├── nap_loader.py                 ← load/validate nap.json, field helpers
    ├── credential_vault.py           ← AES-256 encrypted account storage
    ├── sheets_client.py              ← Google Sheets read/write (all 22 columns)
    ├── email_handler.py              ← inbox polling for verification emails
    ├── listing_qa.py                 ← scrape + score live listing NAP accuracy
    ├── screenshot_manager.py         ← evidence archive, step-named screenshots
    ├── session_logger.py             ← structured JSONL session log per run
    ├── preflight.py                  ← Phase 0: validate everything before starting
    ├── setup_sheet.py                ← one-time Google Sheet header initialization
    ├── reverify.py                   ← Phase 9: scheduled re-verification pass
    └── run_campaign.py               ← main orchestrator (Phases 1-8 + circuit breaker)
```

---

## Google Auth Pattern

**Always follow google-docs.instructions.md.** This skill uses the same pattern:

```python
# Credentials auto-discovered from ~/dotfiles/secrets/*.json
# Venv at ~/dotfiles/secrets/.venv must be active
source ~/dotfiles/secrets/.venv/bin/activate
```

The `SheetsClient` imports `discover_credentials()` from `shared_utils.py`, which uses `glob.glob(os.path.expanduser('~/dotfiles/secrets/*.json'))`. `EmailHandler` uses `discover_credentials()` only for the Gmail API path; the IMAP path uses environment variables directly. If multiple JSON files exist, add `"credentials_file"` to `config.json` to specify which one.

---

## config.json Template

```json
{
  "sheets": {
    "spreadsheet_id": "YOUR_SPREADSHEET_ID_HERE",
    "citations_tab": "Citations",
    "summary_tab": "Summary"
  },
  "email": {
    "verification_account": "citations@yourbusiness.com",
    "business_email": "info@yourbusiness.com",
    "use_gmail_api": false,
    "gmail_subject_user": "",
    "poll_interval_seconds": 60,
    "max_poll_minutes": 15
  },
  "nap_path": "./nap.json",
  "evidence_path": "./evidence/",
  "credentials_path": "./credentials.vault",
  "session": {
    "max_submissions_per_session": 20,
    "domain_cooldown_seconds": 120,
    "circuit_breaker_threshold": 5
  }
}
```

**Do not add `credentials_key` to config.json.** The vault key must only live in `CITATION_VAULT_KEY` env var.

---

## Phase Overview

The orchestrator (`run_campaign.py`) runs these phases per domain. The Google Sheet is updated after every phase — the run is fully resumable.

| Phase | Script                                      | What it does                                                                             |
| ----- | ------------------------------------------- | ---------------------------------------------------------------------------------------- |
| 0     | `preflight.py`                              | Validates NAP, Sheets auth, vault key, email, evidence dir (auto-runs at campaign start) |
| 1     | `run_campaign.py` `_phase1_intel`           | Discovers submission URL, platform type, CAPTCHA, paid gates, existing listings          |
| 2     | `run_campaign.py` `_phase2_account`         | Vault lookup → login or register; email alias strategy                                   |
| 3     | `run_campaign.py` `_phase3_duplicate_check` | Searches directory for conflicting/existing listings                                     |
| 4     | `run_campaign.py` `_phase4_nap_mapping`     | Maps nap.json fields to form selectors (see platform_adapters.md)                        |
| 5     | `run_campaign.py` `_phase5_submit`          | Browser form fill + submit + screenshot evidence                                         |
| 6     | `run_campaign.py` `_phase6_email_verify`    | Polls inbox (IMAP or Gmail API) for verification link                                    |
| 7     | `run_campaign.py` `_phase7_qa`              | Scrapes live listing, scores NAP 0-100, flags discrepancies                              |
| 8     | (circuit breaker)                           | Stops campaign if 5 consecutive failures                                                 |
| 9     | `reverify.py`                               | Scheduled pass: checks pending_review, email_pending, stale verified                     |

---

## Running the Campaign

```bash
# Activate venv first — must be run from project root
source ~/dotfiles/secrets/.venv/bin/activate

# Full campaign (all pending domains)
python -m scripts.run_campaign --config config.json

# Single domain (for testing)
python -m scripts.run_campaign --config config.json --domain hotfrog.com

# Dry run (all phases up to but not including submission)
python -m scripts.run_campaign --config config.json --dry-run

# Pre-flight only
python -m scripts.preflight --config config.json

# Re-verification pass (run separately, e.g. daily cron)
python -m scripts.reverify --config config.json
```

---

## NAP Data (`nap.json`)

Single source of truth. Copy `assets/nap_template.json` and fill it in. The agent reloads `nap.json` fresh for each domain — never caches it across domains.

**Required fields** (campaign will not start without these):

| Field                | Example                                           | Notes                                |
| -------------------- | ------------------------------------------------- | ------------------------------------ |
| `business_name`      | `"Acme Family Chiropractic"`                      | Exact legal name                     |
| `address1`           | `"123 Main St"`                                   | As registered, including directional |
| `city`               | `"Springfield"`                                   |                                      |
| `state`              | `"Illinois"`                                      | Full name                            |
| `state_abbr`         | `"IL"`                                            | Two-letter                           |
| `zip`                | `"62704"`                                         | 5-digit preferred for matching       |
| `phone_e164`         | `"+15551234567"`                                  | +1 then 10 digits, no spaces         |
| `phone_display`      | `"(555) 123-4567"`                                | Human-readable format                |
| `website`            | `"https://acmechiro.example.com/"`                | Must start with https://             |
| `description_short`  | `"Springfield family chiropractor since 2010..."` | ≤160 chars                           |
| `categories_primary` | `"Chiropractor"`                                  |                                      |

Helper functions from `nap_loader.py`:

- `get_field(nap, "business_name", max_length=50)` — with word-boundary truncation
- `get_description(nap, max_length=300)` — picks long → medium → short by available space
- `get_phone(nap, format="digits")` — `display` | `e164` | `digits` | `dashes`
- `normalize_phone(phone)` — strips non-digits, returns last 10 digits
- `normalize_url(url)` — strips scheme, www, trailing slash for comparison

---

## Google Sheet Schema (22 columns, A–V)

| Col | Field               | Type       | Description                    |
| --- | ------------------- | ---------- | ------------------------------ |
| A   | domain              | text       | Citation domain                |
| B   | priority            | 1-5        | 1 = submit first               |
| C   | da_score            | number     | Domain authority               |
| D   | category            | text       | General / Local / Niche        |
| E   | platform_type       | text       | Detected platform type         |
| F   | difficulty          | text       | Easy / Medium / Hard           |
| G   | captcha_type        | text       | none / recaptcha_v2 / hcaptcha |
| H   | submission_url      | url        | Actual submission page URL     |
| I   | status              | text       | See status codes below         |
| J   | email_used          | text       | Account email                  |
| K   | username            | text       | Account username               |
| L   | date_submitted      | datetime   | Submission timestamp           |
| M   | date_verified       | datetime   | Verification timestamp         |
| N   | listing_url         | url        | Live listing URL               |
| O   | confirmation_id     | text       | Submission confirmation        |
| P   | nap_match_score     | 0-100      | NAP accuracy score             |
| Q   | verification_method | text       | email / phone / auto / manual  |
| R   | evidence_path       | text       | Local screenshot archive path  |
| S   | last_checked        | date       | Last QA date                   |
| T   | next_check_due      | date       | Scheduled re-check             |
| U   | notes               | text       | Errors, flags, discrepancies   |
| V   | cost_gate           | TRUE/FALSE | Paid listing only              |

**Status codes:**
`not_started` | `in_progress` | `submitted` | `email_verification_pending` | `pending_review` | `verified` | `verified_partial` | `nap_mismatch` | `duplicate` | `needs_claim` | `paid_only` | `manual_needed` | `captcha_required` | `failed` | `delisted` | `partial_submission` | `already_listed`

**Skipped on campaign start:** `verified`, `duplicate`, `paid_only`, `manual_needed`, `already_listed`

---

## Credential Vault Security

- Key source: `CITATION_VAULT_KEY` environment variable **only**
- Never store key in `config.json`, committed files, or printed to stdout
- Passwords stored inside AES-256 Fernet encrypted blob (vault-level encryption)
- Atomic write: vault written to `.tmp` then renamed — safe against mid-write corruption
- `init_vault()` requires key to be set before it runs

```bash
# Generate key — copy it, store only in env (not in any file)
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
export CITATION_VAULT_KEY="your-generated-key"
```

---

## NAP Match Scoring (`listing_qa.py`)

| Component     | Points | Full match criteria                                       |
| ------------- | ------ | --------------------------------------------------------- |
| Business name | 30     | Exact lowercase match (20 pts for partial/substring)      |
| Phone         | 25     | Last 10 digits match after stripping all non-digits       |
| Address       | 25     | Normalized match (25 pts exact, 15 pts if city+zip match) |
| Website       | 20     | Normalized match: strip scheme, www, trailing slash       |

**Thresholds:** ≥90 → `verified` | ≥70 → `verified_partial` | <70 → `nap_mismatch`

Address normalization contracts full words to abbreviations (Suite→Ste, Street→St, etc.) before comparison, matching the canonical NAP convention.

---

## Error Recovery & Circuit Breaker

Each domain phase is wrapped in try/except. The circuit breaker triggers if 5 consecutive domains fail with unhandled errors — it writes the summary, closes the session log, and exits cleanly.

| Error                          | Recovery                                                        |
| ------------------------------ | --------------------------------------------------------------- |
| Network timeout                | Retry 3× with backoff                                           |
| CAPTCHA challenge              | `captcha_required` → skip, add to manual queue                  |
| Login failed + recovery failed | `manual_needed` → skip                                          |
| Paid gate                      | `paid_only` → skip                                              |
| Account registration failed    | `manual_needed` → skip                                          |
| Form submit failed             | `failed` + error message in notes                               |
| Email verify timeout           | `email_verification_pending` + next_check_due = +24h            |
| Email verify success           | `pending_review` — listing still awaiting directory publication |
| Listing not found after submit | `pending_review` + next_check_due = +3 days                     |

---

## Manual Queue

When `status = manual_needed` or `captcha_required`, the agent flags the domain and moves on. The Sheet `notes` column contains the reason and last step reached.

Review manually: filter Sheet by status = `manual_needed` or `captcha_required`. After manual completion, update status to `submitted` and fill in `date_submitted` and `confirmation_id`.

Common manual items:

- CAPTCHA image challenges (reCAPTCHA v2, hCaptcha)
- Phone verification (SMS/call required)
- Business document upload (license, proof of address)
- Ownership dispute resolution
- 2FA on login

---

## Rate Limiting

- 3-7 second randomized delay between form field fills
- `domain_cooldown_seconds` (default 120s) between domains
- Max 20 submissions per session (configurable)
- Circuit breaker: 5 consecutive failures → stop

---

## Re-verification Pass (`reverify.py`)

Run separately (e.g., daily):

```bash
python -m scripts.reverify --config config.json
```

Processes:

1. `pending_review` / `email_verification_pending` / `submitted` where `next_check_due ≤ today`
2. `verified` / `verified_partial` where `last_checked > 30 days ago` (freshness check)

---

## Chaining

- Citation campaign complete → run `competitor-seo` to compare citation coverage
- NAP mismatches found → run `seo-audit` to assess ranking impact
- Writing listing descriptions → run `geo-optimization` for AI-citable descriptions
