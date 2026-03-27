Output "Read Google Docs." to chat to acknowledge your read this file.

if the document you're working on is related to Google Docs, please read the instructions in this file to ensure your contributions align with the project's standards and guidelines for Google Docs content.

Use the service account credentials provided in the JSON format located in the ~/dotfiles/secrets/ directory to authenticate and interact with Google APIs as needed for your work on Google Docs. Make sure to keep these credentials secure and do not share them publicly.:

Setup (once per machine):
```bash
python3 -m venv ~/dotfiles/secrets/.venv
source ~/dotfiles/secrets/.venv/bin/activate
pip install google-auth google-auth-httplib2 google-api-python-client
```

Before running Google API scripts, activate the venv:
```bash
source ~/dotfiles/secrets/.venv/bin/activate
```

Credentials: Use the service account JSON file in `~/dotfiles/secrets/`. The filename varies per project — find it with `ls ~/dotfiles/secrets/*.json`.

Scopes:
- Read-only: `https://www.googleapis.com/auth/spreadsheets.readonly`
- Read-write: `https://www.googleapis.com/auth/spreadsheets`
- Google Docs: `https://www.googleapis.com/auth/documents.readonly`

Extracting IDs from URLs:
- Spreadsheet: `https://docs.google.com/spreadsheets/d/{SPREADSHEET_ID}/edit`
- Document: `https://docs.google.com/document/d/{DOCUMENT_ID}/edit`

Usage pattern:
```python
import glob
from google.oauth2 import service_account
from googleapiclient.discovery import build

CREDS_FILE = glob.glob(os.path.expanduser('~/dotfiles/secrets/*.json'))[0]
creds = service_account.Credentials.from_service_account_file(CREDS_FILE, scopes=[SCOPE])
service = build('sheets', 'v4', credentials=creds)  # or 'docs', 'v1' for Docs
```

The spreadsheet must be shared with the service account's `client_email` address for access to work.
