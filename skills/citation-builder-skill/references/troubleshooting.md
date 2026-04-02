# Troubleshooting Guide — Citation Builder

## Common Errors and Fixes

---

### Submission Errors

**"Form validation error: Phone number invalid"**

- Most likely cause: Directory expects 10-digit format without formatting
- Fix: Try `phone_e164` digits-only (strip +1), then `phone_display`, then formatted variations
- Script: `nap_loader.get_phone(nap, format="digits")`

**"Business name too long" / field truncation**

- Fix: Some directories cap at 50 or 60 chars — truncate intelligently at word boundary
- Never truncate mid-word
- Script: `nap_loader.get_field(nap, "business_name", max_length=50)`

**"Website URL not valid"**

- Directory may reject URLs with www or without, or with/without trailing slash
- Try: remove www, remove trailing slash, try http:// instead of https://

**"Category not found" in typeahead**

- Try: `categories_secondary` list items one by one
- Try: parent category (e.g., "Plumbing" instead of "Emergency Plumber")
- Try: browse category tree manually via browser

**"Address not recognized" / map pin fails**

- Directory uses Google Maps autocomplete — type slowly and select from dropdown
- Don't paste address; type it character by character into the autocomplete field
- If still fails: enter zip code first, then street address

---

### Account Errors

**"Email already registered"**

- Credential vault should have creds — check vault for this domain
- If not in vault: try password reset flow
- If password reset fails: create new account with different email alias

**"Account suspended / flagged"**

- Note in Sheet, rotate to backup email
- Add original email to `blocked_emails` list in config
- Common causes: too many submissions from same IP, bot-like behavior detected

**Login fails after credential vault lookup**

- Password may have been changed externally
- Try password reset
- If domain uses SSO only (Google/Facebook login): flag as manual_needed

---

### Browser / Automation Errors

**Page loads blank or JS error**

- Reload and retry (up to 3 times)
- Check if JS is required (some forms don't work without JS enabled)
- Screenshot error state and log

**Multi-step form loses state between steps**

- Don't navigate away between steps
- Complete each step without page refresh
- Some forms use session cookies that expire — restart from step 1

**File upload fails**

- Check file size limits (typically 2-5MB per photo)
- Check accepted formats (jpg, png usually safe; webp may not be accepted)
- Compress images manually before adding to `assets/` if over the size limit

---

### Google Sheets Errors

**"Quota exceeded" on Sheets API**

- Slow down write frequency
- Batch updates where possible
- Sheets API free tier: 300 requests/minute, 60 requests/minute per user

**"Range not found" error**

- Column count mismatch — Sheet doesn't have all columns through V
- Run `python -m scripts.setup_sheet --config config.json` to re-initialize headers

---

### Email Verification Errors

**Verification email never arrives**

- Check spam folder (some citation emails trigger spam filters)
- Check the email used for this submission (stored in Sheet `email_used` column)
- Some directories send to the email used for account registration, not the one in the listing

**Verification link expired**

- Most links expire in 24-48 hours
- Re-trigger verification from account settings page
- Script: navigate to account → find "resend verification" option

**Gmail API 403**

- Ensure Gmail API is enabled in Google Cloud project
- Ensure service account has proper Gmail delegation or OAuth scope

---

### NAP Consistency Issues

**NAP match score < 70 after submission**

- Screenshot the live listing
- Note exact discrepancies in Sheet `notes` column
- Common causes: directory auto-formats phone, truncates name, normalizes address
- If critical directory: manually correct via account settings

**Phone displays differently (directory reformatted it)**

- Not a real NAP inconsistency — same number, different display format
- Adjust scoring: normalize both to digits before comparing
- This is handled in `listing_qa.py` — should score as match

---

## Circuit Breaker Triggers

If campaign stops with circuit breaker message, investigate:

1. **Check session logs** in `evidence/session_logs/` for error patterns
2. **Common systemic issues:**
   - IP block from submission site: Try changing IP or VPN, add delays
   - Browser crashed: Restart VS Code Insiders browser
   - Google Sheets rate limited: Reduce write frequency
   - Credential vault corrupted: Restore from backup
   - `nap.json` issue: Validate with `python -m scripts.preflight --config config.json`

---

## Manual Queue Resolution

Filter the Google Sheet by status = `manual_needed` or `captcha_required` daily. Common items:

| Reason                    | Typical Resolution Time | How to Resolve                                    |
| ------------------------- | ----------------------- | ------------------------------------------------- |
| CAPTCHA required          | 2-5 min each            | Complete manually in browser                      |
| Phone verification        | 5-10 min each           | Answer call or enter SMS code                     |
| Document upload           | 10-20 min each          | Prepare document, upload manually                 |
| Unexpected form structure | 15-30 min each          | Complete manually, note field mappings for future |
| Ownership dispute         | 1-7 days                | Contact directory support                         |

After manual completion, update Sheet status to `submitted` or `verified` manually.
