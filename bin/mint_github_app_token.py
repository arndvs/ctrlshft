#!/usr/bin/env python3
"""Mint a short-lived GitHub App installation token.

Required env vars (injected via run-with-secrets.sh):
- GITHUB_APP_ID
- GITHUB_APP_INSTALLATION_ID
- GITHUB_APP_PRIVATE_KEY_B64

Prints JSON to stdout:
{
  "token": "...",
  "expires_at": "..."
}
"""

from __future__ import annotations

import base64
import json
import os
import sys
import time
from typing import Dict


def _fatal(message: str, code: int = 1) -> "None":
    print(message, file=sys.stderr)
    raise SystemExit(code)


def _required_env(name: str) -> str:
    value = os.getenv(name, "").strip()

    if not value:
        _fatal(f"[mint-github-app-token] Missing required environment variable: {name}")

    return value


def _load_dependencies() -> tuple:
    try:
        import jwt  # type: ignore
    except Exception:
        _fatal(
            "[mint-github-app-token] Missing dependency: PyJWT. "
            "Install requirements and rerun bootstrap."
        )

    try:
        import requests  # type: ignore
    except Exception:
        _fatal(
            "[mint-github-app-token] Missing dependency: requests. "
            "Install requirements and rerun bootstrap."
        )

    return jwt, requests


def _decode_private_key(key_b64: str) -> str:
    try:
        key_bytes = base64.b64decode(key_b64, validate=True)
    except Exception:
        _fatal("[mint-github-app-token] GITHUB_APP_PRIVATE_KEY_B64 is not valid base64")

    try:
        pem = key_bytes.decode("utf-8")
    except Exception:
        _fatal("[mint-github-app-token] Decoded private key is not valid UTF-8")

    if "BEGIN" not in pem or "PRIVATE KEY" not in pem:
        _fatal("[mint-github-app-token] Decoded key does not look like a PEM private key")

    return pem


def _build_jwt(app_id: str, private_key_pem: str, jwt_module: object) -> str:
    now = int(time.time())
    payload: Dict[str, int | str] = {
        "iat": now - 60,
        "exp": now + 540,
        "iss": app_id,
    }

    try:
        token = jwt_module.encode(payload, private_key_pem, algorithm="RS256")
    except Exception:
        _fatal("[mint-github-app-token] Failed to sign GitHub App JWT")

    if isinstance(token, bytes):
        return token.decode("utf-8")

    return token


def _request_installation_token(
    installation_id: str,
    app_jwt: str,
    requests_module: object,
) -> Dict[str, str]:
    url = f"https://api.github.com/app/installations/{installation_id}/access_tokens"
    headers = {
        "Authorization": f"Bearer {app_jwt}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "ctrl-mint-github-app-token",
    }

    try:
        response = requests_module.post(url, headers=headers, timeout=20)
    except Exception:
        _fatal("[mint-github-app-token] Network error while requesting installation token")

    if response.status_code >= 400:
        _fatal(
            "[mint-github-app-token] GitHub API error while requesting installation token "
            f"(status={response.status_code}). Check app id, installation id, key format, and clock skew."
        )

    try:
        data = response.json()
    except Exception:
        _fatal("[mint-github-app-token] GitHub API returned non-JSON response")

    token = str(data.get("token", "")).strip()
    expires_at = str(data.get("expires_at", "")).strip()

    if not token:
        _fatal("[mint-github-app-token] GitHub response missing token")

    if not expires_at:
        _fatal("[mint-github-app-token] GitHub response missing expires_at")

    return {"token": token, "expires_at": expires_at}


def main() -> None:
    app_id = _required_env("GITHUB_APP_ID")
    installation_id = _required_env("GITHUB_APP_INSTALLATION_ID")
    key_b64 = _required_env("GITHUB_APP_PRIVATE_KEY_B64")

    if not installation_id.isdigit():
        _fatal("[mint-github-app-token] GITHUB_APP_INSTALLATION_ID must be numeric")

    jwt_module, requests_module = _load_dependencies()
    private_key_pem = _decode_private_key(key_b64)
    app_jwt = _build_jwt(app_id, private_key_pem, jwt_module)
    token_data = _request_installation_token(installation_id, app_jwt, requests_module)

    print(json.dumps(token_data))


if __name__ == "__main__":
    main()
