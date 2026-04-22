---
description: "Security rules for secrets, API keys, credentials, and .env files. Prevents hardcoding secrets in source code."
paths:
  - "**/.env*"
  - "**/secrets/**"
  - "**/*.secret.*"
  - "**/credentials*"
---

# Environment & Secrets Security

- Never hardcode secrets, API keys, or credentials in source code
- Use environment variables or a secrets manager — never commit `.env` files
- Validate that required environment variables exist at startup, not at first use
- Mask secrets in logs and error messages — never log full tokens or keys
- Use separate credentials for development, staging, and production
- Rotate secrets regularly and support zero-downtime rotation
- All secrets and API keys live in environment variables sourced from `~/dotfiles/secrets/.env.agent` (non-sensitive config) or `~/dotfiles/secrets/.env.secrets` (credentials, process-scoped). NEVER hardcode secrets in skill files, config files, scripts, terminal commands, or chat output. Use `os.getenv()` in Python, `process.env` in Node, `$VAR` in bash. If a required env var is missing, throw an error naming the var and pointing to the appropriate .example file for setup
- Secrets in `.env.secrets` are only available at runtime via `~/dotfiles/bin/run-with-secrets.sh <command>`. Non-sensitive config (usernames, hosts, spreadsheet IDs) is in the shell environment from `.env.agent`. Never read secrets from files directly — use `os.getenv()` and rely on the `run-with-secrets.sh` wrapper to inject them
