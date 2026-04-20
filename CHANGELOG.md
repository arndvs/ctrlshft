# Changelog

All notable changes to ctrl+shft are documented here.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

### Added
- Contribution infrastructure for GitHub collaboration:
  - `CHANGELOG.md`
  - `CONTRIBUTING.md`
  - issue templates (`bug-report`, `feature-request`, `skill-request`)
  - pull request template
  - skill lint workflow (`.github/workflows/skill-lint.yml`)

### Changed
- _None yet._

### Fixed
- _None yet._

---

## [0.1.0] - YYYY-MM-DD

### Added
- `bootstrap.sh` — idempotent setup script for macOS, Linux, and WSL
- `CLAUDE.md` generated from `CLAUDE.base.md` with local instruction refs
- core skills and agent/rule scaffolding
- `detect-context.sh` — scans working directory and loads matching rule files
- `run-with-secrets.sh` — injects process-scoped credentials into child processes
- `validate-env.sh` — validates environment setup including AFK credential chain
- `verify-github-app-token.sh` — confirms GitHub App token minting works correctly
- three-tier secrets model: `.env.agent`, `.env.secrets`, ephemeral AFK tokens
- supply chain hardening: `min-release-age` for npm, `exclude-newer` for uv
- `shft` — bash loop for AFK autonomous agent runs in Docker sandbox
- ctrlshft.dev landing page
