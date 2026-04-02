# Setup Guide

## Prerequisites

### 1. Python Venv (per google-docs.instructions.md)

```bash
# Only once per machine — skip if venv already exists
python -m venv ~/dotfiles/secrets/.venv
source ~/dotfiles/secrets/.venv/bin/activate   # Linux/Mac
# Windows: ~/dotfiles/secrets/.venv/Scripts/activate

pip install google-auth google-auth-httplib2 google-api-python-client cryptography
```

Before every session:
```bash
source ~/dotfiles/secrets/.venv/bin/activate
```

### 2. Google Service Account

The skill uses the same credentials as other skills in your dotfiles:

1. Confirm `~/dotfiles/secrets/*.json` contains your service account file
2. If multiple JSON files exist, add `"credentials_file": "/path/to/specific.json"` to `config.json`
3. Enable **Google Sheets API** in the Google Cloud project that owns the service account
4. Share your citation spreadsheet with the service account's `client_email`

```bash
# Confirm discovery works
python -c "
import glob, os, json
matches = glob.glob(os.path.expanduser('~/dotfiles/secrets/*.json'))
print('Found:', matches)
with open(matches[0]) as f:
    data = json.load(f)
print('client_email:', data.get('client_email'))
"
```

### 3. Credential Vault

```bash
# Generate key — copy the output, NEVER paste it into any file
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"

# Set it in your shell (add to ~/.bashrc or ~/.zshrc to persist)
export CITATION_VAULT_KEY="paste-generated-key-here"

# Initialize empty vault (key must be set first)
python -c "from scripts.credential_vault import init_vault; init_vault('credentials.vault')"
```

**Security rules:**
- Key lives ONLY in `CITATION_VAULT_KEY` env var
- Never store key in `config.json`, git-tracked files, or print it

### 4. NAP Data

```bash
cp assets/nap_template.json nap.json
# Edit nap.json — fill in all required fields
# Validate:
python -c "from scripts.nap_loader import load_nap; load_nap('nap.json'); print('NAP valid')"
```

### 5. Google Sheet

1. Create a new Google Sheet
2. Note the Spreadsheet ID from the URL: `https://docs.google.com/spreadsheets/d/{ID}/edit`
3. Create two tabs named exactly: `Citations` and `Summary`
4. Share the sheet with the service account `client_email`
5. Initialize headers:
   ```bash
   python -m scripts.setup_sheet --config config.json
   ```
6. Add your citation domains to column A (Citations tab), one per row starting at row 2

### 6. Email for Verifications

**Option A: IMAP (simpler)**

```bash
export CITATION_EMAIL="citations@yourdomain.com"
export CITATION_EMAIL_PASSWORD="your-password"
export CITATION_IMAP_HOST="imap.yourdomain.com"  # or imap.gmail.com for Gmail
```

Set `use_gmail_api: false` in `config.json`.

Use a dedicated email account for citations. Do not use your main business inbox.

**Option B: Gmail API (requires domain-wide delegation)**

Gmail API with a service account requires **domain-wide delegation** — the service account must be granted access to impersonate a Google Workspace user.

Setup steps:
1. In Google Workspace Admin Console: Security → API Controls → Domain-wide Delegation
2. Add the service account client ID with scope: `https://www.googleapis.com/auth/gmail.readonly`
3. Set in `config.json`:
   ```json
   "email": {
     "use_gmail_api": true,
     "gmail_subject_user": "citations@yourworkspacedomain.com"
   }
   ```

Without domain-wide delegation, Gmail API calls with `userId="me"` will return 403. If you don't have Google Workspace admin access, use IMAP instead.

### 7. Pre-flight Check

```bash
python -m scripts.preflight --config config.json
```

All items must show ✓ before running campaign.

---

## Full Environment Variable List

```bash
# Required
export CITATION_VAULT_KEY="your-fernet-key"

# Required for IMAP email (not needed if use_gmail_api=true)
export CITATION_EMAIL="citations@yourdomain.com"
export CITATION_EMAIL_PASSWORD="your-password"
export CITATION_IMAP_HOST="imap.yourdomain.com"
```

No `GOOGLE_APPLICATION_CREDENTIALS` needed — credentials auto-discovered from `~/dotfiles/secrets/*.json`.
