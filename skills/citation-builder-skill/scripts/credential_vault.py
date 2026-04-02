"""
credential_vault.py — Encrypted credential storage for citation directory accounts.

Passwords are stored inside an AES-256 (Fernet) encrypted blob.
The vault key must be set via the CITATION_VAULT_KEY environment variable.
NEVER store the key in config.json or print it to stdout.

Usage:
    from scripts.credential_vault import init_vault, get_credentials, store_credentials

    init_vault("credentials.vault")  # run once
    store_credentials("credentials.vault", "yelp.com", "user@email.com", "password123")
    creds = get_credentials("credentials.vault", "yelp.com")
"""

import json
import os
import tempfile
from pathlib import Path
from datetime import datetime

try:
    from cryptography.fernet import Fernet, InvalidToken
except ImportError:
    raise ImportError(
        "cryptography package required. Install with:\n"
        "  pip install cryptography"
    )


def _get_fernet() -> Fernet:
    """
    Load Fernet cipher from CITATION_VAULT_KEY env var.
    Key must be a valid Fernet key (44-char URL-safe base64 encoding of 32 bytes).
    Generate one with: python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
    Raises EnvironmentError if key not set, ValueError if key is invalid.
    """
    key = os.environ.get("CITATION_VAULT_KEY", "").strip()
    if not key:
        raise EnvironmentError(
            "CITATION_VAULT_KEY environment variable is not set.\n"
            "Set it with: export CITATION_VAULT_KEY='your-key-here'\n"
            "Generate a new key with: python -c \"from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())\""
        )

    try:
        return Fernet(key.encode())
    except Exception as e:
        raise ValueError(
            f"CITATION_VAULT_KEY is not a valid Fernet key: {e}\n"
            "Generate a valid key with: python -c \"from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())\"\n"
            "If your existing vault can't be decrypted, re-initialize with init_vault()."
        ) from e


def init_vault(vault_path: str) -> None:
    """
    Initialize an empty encrypted vault file.
    Run once during setup. Does not print or return the key.
    Prints instructions for generating a key if CITATION_VAULT_KEY is not set.
    """
    path = Path(vault_path)
    if path.exists():
        print(f"Vault already exists at {vault_path} — skipping init.")
        return

    # This will raise EnvironmentError if key not set — intentional.
    # User must set key BEFORE initializing vault.
    fernet = _get_fernet()
    encrypted = fernet.encrypt(json.dumps({}).encode())
    path.write_bytes(encrypted)
    print(f"Empty vault initialized at {vault_path}")
    print("Key source: CITATION_VAULT_KEY environment variable (already set).")


def _load_vault_raw(vault_path: str) -> dict:
    """Decrypt and load vault. Returns empty dict if file doesn't exist."""
    path = Path(vault_path)
    if not path.exists():
        return {}
    fernet = _get_fernet()
    try:
        encrypted = path.read_bytes()
        decrypted = fernet.decrypt(encrypted)
        return json.loads(decrypted)
    except InvalidToken:
        raise ValueError(
            f"Failed to decrypt vault at {vault_path}. "
            "Check that CITATION_VAULT_KEY matches the key used when vault was created."
        )


def _save_vault_raw(vault_path: str, vault: dict) -> None:
    """Encrypt and atomically write vault to disk."""
    fernet = _get_fernet()
    encrypted = fernet.encrypt(json.dumps(vault, indent=2).encode())
    path = Path(vault_path)
    fd, tmp_path = tempfile.mkstemp(dir=path.parent, suffix=".tmp")
    try:
        os.write(fd, encrypted)
        os.close(fd)
        fd = -1
        Path(tmp_path).replace(path)
    except Exception:
        if fd >= 0:
            os.close(fd)
        Path(tmp_path).unlink(missing_ok=True)
        raise


def get_credentials(vault_path: str, domain: str) -> dict | None:
    """
    Get credentials for a domain. Returns None if not found.
    Returned dict has keys: email, password, username, account_url, created_date, last_updated.
    """
    vault = _load_vault_raw(vault_path)
    return vault.get(domain)


def store_credentials(
    vault_path: str,
    domain: str,
    email: str,
    password: str,
    username: str = "",
    account_url: str = "",
) -> None:
    """
    Store or update credentials for a domain.
    Passwords are stored inside the encrypted vault blob (not individually encrypted,
    but protected by the vault's AES-256 encryption).
    """
    vault = _load_vault_raw(vault_path)
    now = datetime.now().strftime("%Y-%m-%d")
    existing = vault.get(domain, {})
    vault[domain] = {
        "email": email,
        "password": password,          # protected by vault-level AES-256 encryption
        "username": username,
        "account_url": account_url,
        "created_date": existing.get("created_date", now),
        "last_updated": now,
    }
    _save_vault_raw(vault_path, vault)


def validate_vault_key() -> None:
    """Validate that CITATION_VAULT_KEY is set and is a valid Fernet key."""
    _get_fernet()
