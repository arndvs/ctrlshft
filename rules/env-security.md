---
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
