# Skill QA Checklist

Run through this checklist after generating a new skill. Every item must pass before the skill is considered complete.

---

## Structure

- [ ] Skill directory is at `~/dotfiles/skills/{skill-name}/`
- [ ] Directory name is kebab-case
- [ ] `SKILL.md` exists at root of skill directory
- [ ] `SKILL.md` has YAML frontmatter with `name` and `description`
- [ ] `description` includes trigger phrases for when to invoke the skill
- [ ] `config.example.json` exists with all keys and placeholder values
- [ ] `scripts/__init__.py` exists with entry point docstring
- [ ] `references/setup.md` exists with environment setup guide

## SKILL.md Completeness

- [ ] First-Time Setup section with step-by-step instructions
- [ ] File Structure section listing all files with descriptions
- [ ] Config Template section with full JSON example
- [ ] Phase Overview table (Phase | What it does)
- [ ] Running section with CLI commands (full, single-item, dry-run, preflight)
- [ ] State Store Schema section (columns, types, descriptions)
- [ ] Status Codes section with all valid statuses
- [ ] Error Recovery table (error → recovery action)
- [ ] Rate Limiting section (delays, cooldowns, session limits)

## Python Code Quality

- [ ] All imports resolve (no missing dependencies)
- [ ] No hardcoded secrets — all from env vars via `os.environ.get()`
- [ ] No TODOs, placeholders, or `pass` in production code
- [ ] No `# comment` lines (by convention)
- [ ] All scripts run from project root: `python -m scripts.{module}`
- [ ] Every function that can fail raises a descriptive error (never fails silently)
- [ ] No sample data or fallback values (`||`, `??`, or `or ""`)

## Config + Secrets

- [ ] `config.example.json` has every key referenced in `validate_config()`
- [ ] `validate_config()` rejects placeholder values like `YOUR_*_HERE`
- [ ] Sensitive values come from env vars, not config file
- [ ] Resolution order documented: env var → config.json → auto-discovery
- [ ] `load_config()` overlays env vars onto config values

## State Management

- [ ] State store updated after every phase (resumability guarantee)
- [ ] Status codes validated before writing
- [ ] `get_pending_items()` correctly filters already-completed items
- [ ] Retry/resume after crash picks up where it left off
- [ ] Summary/aggregate stats auto-computed

## Error Handling

- [ ] Circuit breaker configured with sensible threshold
- [ ] Circuit breaker resets on success
- [ ] Pre-execution failures mark item as `failed`
- [ ] Post-execution failures append notes only (never revert status)
- [ ] Session logger captures every phase start, end, and error
- [ ] Session logger captures full tracebacks for errors
- [ ] Preflight validates ALL dependencies before starting (never fails one-at-a-time)

## Browser Automation (if applicable)

- [ ] SKILL.md instructs agent to load browser tools via `tool_search_tool_regex`
- [ ] Phase docstrings tell agent exactly what to do with browser
- [ ] Screenshot evidence captured at key steps
- [ ] Evidence directory uses sanitized work-unit names (no path traversal)
- [ ] Rate limiting between browser interactions (3-7s random delay)
- [ ] If dual-mode: `browser_adapter.py` has both VS Code and Playwright implementations
- [ ] If dual-mode: entry point checks `SKILL_MODE` env var

## Google Sheets (if applicable)

- [ ] Service account auto-discovered via `discover_credentials()`
- [ ] `setup_sheet.py` writes headers correctly
- [ ] Exponential backoff on 429 rate limit responses
- [ ] Column mapping (`COL` dict) matches `HEADERS` list exactly
- [ ] Summary tab auto-updated after each run

## Evidence & Logging

- [ ] Evidence root directory auto-created if missing
- [ ] Screenshots named with step order prefix: `NN_stepname_HHMMSS.png`
- [ ] Session logs in `{evidence}/session_logs/session_{timestamp}.jsonl`
- [ ] Session log has start and end bookend events
- [ ] No credential data in logs or evidence filenames
