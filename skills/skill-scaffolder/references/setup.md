# Setup Guide — Skill Scaffolder

This skill generates new agent skills. It doesn't require its own venv or dependencies — it produces files that the generated skill will need.

---

## Prerequisites

### For the Skill Scaffolder Itself

None. This skill only generates files — no runtime dependencies.

### For Generated Skills That Use Google Sheets

```bash
source ~/dotfiles/secrets/.venv/bin/activate
pip install google-auth google-auth-httplib2 google-api-python-client
```

Ensure `~/dotfiles/secrets/*.json` contains a GCP service account key with Sheets API enabled.

### For Generated Skills That Use Encrypted Vault

```bash
source ~/dotfiles/secrets/.venv/bin/activate
pip install cryptography
```

### For Generated Skills That Use Playwright (VPS mode)

```bash
pip install playwright
playwright install chromium
```

### For Generated Skills That Use Email Verification

IMAP:
```bash
export {PREFIX}_EMAIL="citations@yourdomain.com"
export {PREFIX}_EMAIL_PASSWORD="your-password"
export {PREFIX}_IMAP_HOST="imap.gmail.com"
```

Gmail API: Requires domain-wide delegation. See citation-builder-skill's `references/setup.md` for full instructions.

---

## After Generating a New Skill

1. `cd ~/dotfiles/skills/{new-skill-name}/`
2. Copy `config.example.json` to `config.json`
3. Fill in config values
4. Set config in `~/dotfiles/secrets/.env.agent`, credentials in `~/dotfiles/secrets/.env.secrets`
5. Run preflight: `python -m scripts.preflight --config config.json`
6. Fix any errors shown
7. Run dry: `python -m scripts.run_{name} --config config.json --dry-run`
8. Run live: `python -m scripts.run_{name} --config config.json`

---

## Skill Location

All skills live at `~/dotfiles/skills/` which is symlinked to `~/.claude/skills`. This is the single source of truth across all machines. Generated skills are immediately available to the agent after creation.

---

## Google Auth Pattern

All generated skills that use Google APIs follow the same pattern from `google-docs.instructions.md`:

```python
from scripts.shared_utils import discover_credentials

creds_file = discover_credentials(config)
```

Resolution order:
1. `GCP_CREDENTIALS_FILE` environment variable
2. `config["credentials_file"]` if set
3. Auto-discovery: glob `~/dotfiles/secrets/*.json` for service account files

If multiple JSON files exist in secrets/, specify which one via env var or config.
