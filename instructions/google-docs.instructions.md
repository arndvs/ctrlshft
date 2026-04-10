Output "Read Google Docs instructions." to chat to acknowledge you read this file.

If the task involves Google Sheets, Docs, or Slides, follow these instructions to authenticate and interact with Google APIs. Keep credentials secure and never share them publicly.

Always write Google API scripts to a temp file using `create_file` first, then execute with a one-line command. Never inline multi-line Python in terminal commands.

Use the service account credentials in the `~/dotfiles/secrets/` directory.

Setup (once per machine — skip if .venv already exists):

```bash
# `python` works on both machines — Linux has a symlink: python -> python3 -> python3.13
python -m venv ~/dotfiles/secrets/.venv
source ~/dotfiles/secrets/.venv/bin/activate
pip install google-auth google-auth-httplib2 google-api-python-client
```

On Windows the activate script is at `Scripts/activate` instead of `bin/activate`. Detect the OS and use the correct path.

Before running Google API scripts, activate the venv:

```bash
source ~/dotfiles/secrets/.venv/bin/activate
```

Credentials: Resolved via the `GCP_CREDENTIALS_FILE` environment variable (preferred), or auto-discovered from `~/dotfiles/secrets/*.json` if only one JSON file exists. Set the env var in `~/dotfiles/secrets/.env.agent`.

Scopes:

- Sheets read-only: `https://www.googleapis.com/auth/spreadsheets.readonly`
- Sheets read-write: `https://www.googleapis.com/auth/spreadsheets`
- Docs read-only: `https://www.googleapis.com/auth/documents.readonly`
- Docs read-write: `https://www.googleapis.com/auth/documents`
- Slides read-only: `https://www.googleapis.com/auth/presentations.readonly`
- Slides read-write: `https://www.googleapis.com/auth/presentations`
- Drive read-only: `https://www.googleapis.com/auth/drive.readonly`
- Drive read-write: `https://www.googleapis.com/auth/drive`

Extracting IDs from URLs:

- Spreadsheet: `https://docs.google.com/spreadsheets/d/{SPREADSHEET_ID}/edit`
- Document: `https://docs.google.com/document/d/{DOCUMENT_ID}/edit`
- Slides: `https://docs.google.com/presentation/d/{PRESENTATION_ID}/edit`

Service and version lookup:

| Product | Service name | Version | Scope keyword   |
| ------- | ------------ | ------- | --------------- |
| Sheets  | `sheets`     | `v4`    | `spreadsheets`  |
| Docs    | `docs`       | `v1`    | `documents`     |
| Slides  | `slides`     | `v1`    | `presentations` |
| Drive   | `drive`      | `v3`    | `drive`         |

Usage pattern:

```python
import os
import glob
from google.oauth2 import service_account
from googleapiclient.discovery import build

SCOPES = ['https://www.googleapis.com/auth/spreadsheets']  # adjust per task — see scopes list above

def _resolve_credentials():
    env_path = os.environ.get('GCP_CREDENTIALS_FILE', '').strip()
    if env_path:
        expanded = os.path.expanduser(env_path)
        if not os.path.exists(expanded):
            raise FileNotFoundError(f'GCP_CREDENTIALS_FILE points to missing file: {expanded}')
        return expanded
    import json as _json
    matches = [
        f for f in glob.glob(os.path.expanduser('~/dotfiles/secrets/*.json'))
        if _json.load(open(f)).get('type') == 'service_account'
    ]
    if not matches:
        raise FileNotFoundError('No service account JSON found. Set GCP_CREDENTIALS_FILE or place one in ~/dotfiles/secrets/')
    if len(matches) > 1:
        raise RuntimeError(f'Multiple service account JSONs in ~/dotfiles/secrets/: {matches} — set GCP_CREDENTIALS_FILE env var')
    return matches[0]

CREDS_FILE = _resolve_credentials()
creds = service_account.Credentials.from_service_account_file(CREDS_FILE, scopes=SCOPES)
service = build('sheets', 'v4', credentials=creds)  # e.g. build('docs', 'v1', ...) — see table above
```

The spreadsheet/document must be shared with the service account's `client_email` address for access to work. If you get a 403 or "not found" error, the most likely cause is the document isn't shared with the service account — the API error message is often misleading.

Service account credentials auto-refresh, so no manual token handling is needed.
