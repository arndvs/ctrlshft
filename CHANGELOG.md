# Changelog

All notable changes to ctrl+shft are documented here.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

Slice 7.1: HUD event producers, daemon upgrade, compliance polish.

### Added
- `bin/ctrlshft-claude` — event-producing wrapper that parses Claude stdout for compliance/context events
- WebSocket server (ws://localhost:7822) for real-time HUD event broadcasts
- SQLite persistence via optional `better-sqlite3` (falls back to in-memory + JSONL)
- Server-side file inventory scan (skills, agents, rules, instructions, hooks)
- `package.json` + `package-lock.json` for optional `better-sqlite3` dependency
- `cspell.json` — initial cSpell configuration

### Changed
- `bin/hud-daemon.js` upgraded from HTTP polling to WebSocket + adaptive polling fallback
- `hud/index.html` upgraded with project tabs, file inventory sidebar, session management
- `bin/detect-context.sh` now emits context events to HUD pipeline on every `cd()`
- `bin/write-hud-state.sh` architecture diagram and API table corrected

### Fixed
- `ctrlshft-claude` wrapper: JSONL fallback when pipe unavailable, EXIT trap for cleanup, exit code preservation
- 5 event-producer bugs from 7.1a audit (timestamp format, payload shape, error handling)
- HUD: renamed `esc`→`str` helper, removed dead CSS class, replaced `setInterval` with `setTimeout`

---

## [0.7.0] - 2026-04-21

Slice 7: HUD UI + compliance skills (#48).

### Added
- `hud/index.html` — HUD UI (single-file, dark theme, WebSocket + adaptive polling)
- `skills/compliance-audit/SKILL.md` — auto-invoked rule compliance check after do-work/tdd/debugging
- `skills/stress-test/SKILL.md` — adversarial 19-scenario protocol for rule boundary validation

### Changed
- `bin/hud-daemon.js` serves HUD from `hud/index.html` (moved from `working/`)
- README: rebuilt directory tree (added 8 bin/ scripts, hooks/, clients/, hud/, docs files)
- README: skills table updated from 16 → 18 entries
- README: observability section updated to reflect shipped HUD
- README: added Hooks section documenting 6 lifecycle hooks
- `docs/observability-benchmarking-plan.md` updated with shipped status markers

---

## [0.7.0] - 2026-04-21

Slice 7: compliance dashboard UI + compliance skills (#48).

### Added
- `dashboard/index.html` — compliance dashboard UI (single-file, dark theme, 5s polling)
- `skills/compliance-audit/SKILL.md` — auto-invoked rule compliance check after do-work/tdd/debugging
- `skills/stress-test/SKILL.md` — adversarial 19-scenario protocol for rule boundary validation

### Changed
- `bin/dashboard-daemon.js` serves dashboard from `dashboard/index.html` (moved from `working/`)
- README: rebuilt directory tree (added 8 bin/ scripts, hooks/, clients/, dashboard/, docs files)
- README: skills table updated from 16 → 18 entries
- README: observability section updated to reflect shipped compliance dashboard
- README: added Hooks section documenting 6 lifecycle hooks
- `docs/observability-benchmarking-plan.md` updated with shipped status markers

---

## [0.6.0] - 2026-04-21

Slices 4–6: migration toolchain, client scope, HUD backend (#46).

### Added
- `bin/migrate.sh`, `bin/uninstall.sh`, `bin/_adopt.sh` — migration and adopt toolchain
- `bootstrap.sh` modes: `--adopt`, `--minimal`, `--check`, `--force`
- `bin/detect-client.sh`, `bin/new-client.sh` — per-client instruction isolation
- `clients/` directory with `_template/` scaffolding for project-scoped instructions
- `bin/write-hud-state.sh` — non-blocking event emitter (pipe → HTTP → JSONL fallback)
- `bin/hud-daemon.js` — Node.js HTTP server (`/api/state`, `/healthz`, `POST /api/event`)
- `bin/start-hud.sh` — daemon lifecycle manager (start/stop/status/restart)
- `bin/detect-context.sh` hook to emit context events to HUD pipeline
- `docs/observability-benchmarking-plan.md` — tracked observability plan
- `docs/readme-site-deep-audit.md` — audit findings report
- `.gitattributes` enforcing LF line endings for all text files

### Fixed
- README observability link pointed to deleted `working/` path
- `site/index.html` prerequisite listed `sbx` instead of `srt`
- Duplicate contributors section in `site/index.html` (invalid DOM)
- `.gitattributes` comment mismatch (said per-platform, behavior was force-LF)
- `.gitignore` merge conflicts resolved (keep client scope rules)
- Workflow YAML blank spacer lines removed for parser compat

---

## [0.5.0] - 2026-04-18

CI, contribution infrastructure, and contributors section (#38–#46 prep).

### Added
- `.github/workflows/integrity.yml` — source-of-truth policy CI
- `.github/workflows/skill-lint.yml` — skill file structure linting
- `CONTRIBUTING.md`, issue templates (`bug-report`, `feature-request`, `skill-request`), PR template
- Dynamic contributors section on ctrlshft.dev (GitHub API, rate-limit fallback, safe DOM rendering)
- CI mode and policy checks in `validate-env.sh`
- Integrity badge in README

### Changed
- Global instructions trimmed from 36 to 30 rules
- Project name normalized to `ctrl+shft` across README and site
- Source-of-truth block added to `CLAUDE.base.md`
- Counter-directive for VS Code Insiders rule-loading bug

### Fixed
- Stale handoff reference in document skill
- `gh` path exposure in Windows Git Bash

### Removed
- `dotfiles.code-workspace` from tracked files
- `global.instructions.md.bak` from tracked files

---

## [0.4.0] - 2026-04-17

Landing page, site infrastructure, and architect skill (#28–#37).

### Added
- `site/index.html` — ctrlshft.dev landing page with dark mode, accordion install, contributor grid
- `LICENSE` (MIT)
- GitHub Pages / Vercel deployment setup
- `docs/CNAME` for custom domain
- `docs/assets/og-repo-card.html` — social preview card
- Architect skill (renamed from technical-fellow) with `/architect` pipeline step
- Slash command wrappers for 7 core skills (`commands/`)
- `bootstrap.sh` step 6: symlink `commands/` to `~/.claude/commands/`
- Claude Code lifecycle hooks with bootstrap wiring (compaction guard, context-warning stub)
- Atomic commits skill with branch isolation + PR workflow
- UX/UI prototyping instructions for marketers

### Changed
- Landing page moved from `docs/` to `site/` (#36)
- Dark mode color hierarchy refined to 4 tiers
- Layout migrated from px to rem with 110% base scale
- `assets/` consolidated into `docs/assets/`
- Bootstrap centralized symlink management

### Fixed
- Hero terminal stacked below text on mobile
- Merge artifacts in install step 1
- `sbx` → `srt` prerequisite rename
- `validate-env.sh` checks `.env.secrets` file when credentials not in env

---

## [0.3.0] - 2026-04-10

Hardening, security, and cross-conversation continuity (#22–#27).

### Added
- Cross-conversation continuity in codebase-audit and explore skills
- CSS instructions with comprehensive stack, color system, typography, and accessibility rules
- Agent definitions: code-reviewer, researcher, security-auditor
- `bootstrap.sh` expanded to include agents and rules directories

### Changed
- README rewritten to match codebase voice — concrete over aspirational
- Logo updated to `ctrl-inverted.png`

### Fixed
- Security: cleanup trap for secrets temp file in `run-with-secrets.sh`
- Security: hardened prompt injection sanitizer in `_build_prompt.sh`
- `_lib.sh` leaked loop variable and venv overwrite
- `detect-context.sh` detection gaps
- `sync-settings.sh` error messages use `red()` helper
- Bootstrap deduplicated step 7 via `validate-env.sh`
- Portable sed, stdin piping, cleanup traps in shft scripts
- Portable lock and variable hygiene in shft scripts
- Instructions: Netlify edge function → Next.js Edge Runtime (#16)
- Instructions: Google Docs API vs uploaded files clarification

---

## [0.2.0] - 2026-04-09

Skills, digest, and structural refactors (#1–#6).

### Added
- GitHub weekly digest skill with daily/weekly cron wrappers (`daily_digest.sh`, `weekly_rollup.sh`)
- Rollup-specific narrative prompt for weekly digests
- Exploration instructions for codebase auditing and investigation
- PRD writing skill with module sketching and detailed template
- Docker Compose v2 detection (`compose.yaml`/`.yml`)

### Changed
- `ralph` renamed to `shift` (#6), later to `shft`
- `local/` renamed to `_local/` for sort-to-top visibility (#5)
- Skill-scaffolder promoted from `_local/` to global
- PHP instructions refined (removed outdated guidelines)
- Personal files separated into gitignored `_local/` directories (#5)

### Fixed
- Dead references in systematic-debugging skill
- Tool reference in explore skill
- Duplicate grill-me instructions in write-a-prd
- Technical-fellow vs prd-to-issues boundary clarified
- `ANTHROPIC_API_KEY` and `GITHUB_TOKEN` added to secrets template
- Compaction warning added to global instructions

---

## [0.1.0] - 2026-04-08

Initial release — bootstrap, secrets, AFK loop, core skills.

### Added
- `bootstrap.sh` — idempotent setup script for macOS, Linux, and WSL
- `CLAUDE.md` generated from `CLAUDE.base.md` with local instruction refs
- `detect-context.sh` — scans working directory and loads matching rule files
- `run-with-secrets.sh` — injects process-scoped credentials into child processes
- `validate-env.sh` — validates environment setup including AFK credential chain
- `verify-github-app-token.sh` — confirms GitHub App token minting works correctly
- Three-tier secrets model: `.env.agent`, `.env.secrets`, ephemeral AFK tokens
- Supply chain hardening: `min-release-age` for npm, `exclude-newer` for uv
- `shft` — bash loop for AFK autonomous agent runs in Docker sandbox
- Core skills: explore, grill-me, do-work, write-a-prd, prd-to-issues, codebase-audit, systematic-debugging, tdd, research, improve-architecture
- Agent and rule scaffolding
- `agent-shell.sh` for AI agent shell integration
- Global instructions with skill self-learning
- Domain-specific instructions: Next.js, PHP, Sanity, Sentry, Google Docs
- ctrlshft.dev landing page
