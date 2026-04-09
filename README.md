# AI Dotfiles

Opinionated VS Code + GitHub Copilot configuration that makes AI agents follow strict coding conventions and produce production-quality code — shared across local machines and a VPS from a single source of truth.

Forked from [kangarko/ai-files](https://github.com/kangarko/ai-files) and extended with environment hardening, cross-machine secret management, auto-context detection, custom skills, and a shared Python runtime for automation scripts.

## What This Repo Does

Clone to `~/dotfiles` on every machine (Windows, Linux VPS, macOS). One `git pull` updates instructions, skills, secrets templates, and shell config everywhere.

```
~/dotfiles/                     ← this repo, cloned on every machine
├── CLAUDE.md                   ← entry point — tells agents which instructions to load
├── global.instructions.md      ← universal coding rules (DRY, error handling, CSS, JS)
├── settings.json               ← VS Code settings (Copilot, Claude Code, editor prefs)
├── instructions/               ← domain-specific instruction files
│   ├── nextjs.instructions.md      Next.js 16 / TypeScript / React 19
│   ├── php.instructions.md         PHP 8.4+ OOP
│   ├── sanity.instructions.md      Sanity CMS MCP tools reference
│   ├── sentry.instructions.md      Sentry MCP tools reference
│   ├── google-docs.instructions.md Google API (Sheets, Docs, Slides, Drive)
│   ├── codebase-audit.instructions.md  Audit methodology
│   ├── exploration.instructions.md     Codebase exploration and investigation
│   ├── technical-fellow.instructions.md Technical fellow planning role
│   └── atomic-commits.md              Atomic commit workflow rules
├── skills/                     ← custom skills (auto-discovered by VS Code)
│   ├── citation-builder-skill/     automated SEO citation building pipeline
│   ├── github-weekly-digest/       GitHub commits → AI analysis → blog post → Sanity CMS
│   ├── portfolio-showcaser/        browser-driven portfolio screenshots + reports
│   ├── skill-scaffolder/           meta-skill for creating new agent skills
│   └── systematic-debugging/       root-cause-first debugging methodology
├── prompts/                    ← reusable prompt templates
│   ├── codebase-audit.txt          ruthless audit prompt
│   └── technical-fellow.md         technical fellow planning format
├── bin/                        ← shell scripts sourced in .bashrc
│   ├── load-secrets.sh             sources secrets/.env.agent into shell (non-sensitive only)
│   ├── run-with-secrets.sh         injects secrets/.env.secrets into a child process
│   ├── detect-context.sh           auto-detects project type → ACTIVE_CONTEXTS
│   ├── bootstrap.sh                one-command setup for a fresh machine
│   └── sync-settings.sh            merge VS Code settings from dotfiles
├── secrets/                    ← GITIGNORED — per-machine secrets
│   ├── .env.agent                  non-sensitive config (from .env.agent.example)
│   ├── .env.secrets                credentials/tokens (from .env.secrets.example)
│   ├── .env                        legacy (kept during migration)
│   ├── *.json                      GCP service account credentials
│   └── .venv/                      shared Python venv for Google API scripts
├── working/                    ← GITIGNORED — scratch files, migration scripts
├── .env.example                ← legacy template (kept for reference)
├── .env.agent.example          ← template for secrets/.env.agent (non-sensitive config)
└── .env.secrets.example        ← template for secrets/.env.secrets (credentials)
```

## How It Works

### Instruction Loading Chain

```
VS Code opens any project
  ↓
chat.instructionsFilesLocations: {"~/dotfiles": true}
  ↓ discovers
CLAUDE.md → @global.instructions.md → conditional @instructions/*.md
  ↓ based on workspace files
detect-context.sh → ACTIVE_CONTEXTS=nextjs,prisma,sanity
  ↓ agents load only matching skills
skills/citation-builder-skill/SKILL.md (if relevant)
```

**Claude Code (CLI)** reads `~/.claude/CLAUDE.md` which references the same instruction files via `@` paths.

**VS Code Copilot** discovers instructions and skills by scanning the `~/dotfiles` tree via the `chat.instructionsFilesLocations` setting.

### Environment Hardening

Secrets are split into two tiers — agents see config but never credentials:

| File | Sourced into shell? | Agent-visible? | Contents |
|---|---|---|---|
| `secrets/.env.agent` | Yes (via `load-secrets.sh`) | Yes (in shell env) | Usernames, hosts, spreadsheet IDs, flags |
| `secrets/.env.secrets` | **No** | **No** | API keys, tokens, passwords |

**How secrets reach scripts:**

1. `load-secrets.sh` sources **only** `.env.agent` into the shell (added to `.bashrc`)
2. Scripts that need credentials run via `bin/run-with-secrets.sh`:
   ```bash
   ~/dotfiles/bin/run-with-secrets.sh python scripts/sheets_client.py
   ```
   This injects `.env.secrets` into the child process only — secrets vanish when it exits
3. Scripts read everything from `os.environ` / `process.env` / `$VAR` as before
4. If missing → hard error naming the var and pointing to the appropriate `.example` file

**Agent-level protections:**

- Claude Code deny rules in `~/.claude/settings.json` block `env`, `printenv`, `cat secrets/*`, and `echo $*KEY*` patterns
- Secrets are never in the shell environment, so agents can't accidentally inherit them
- `bin/validate-env.sh` checks that secrets are NOT leaking into the shell

> **Setting up deny rules on a new machine/VPS:** The deny rules in `~/.claude/settings.json` are machine-local (not in this repo). After bootstrap, run `validate-env.sh` — if it warns about missing deny rules, copy the `"deny"` array from your local `~/.claude/settings.json` to the new machine's. The rules block agents from running `env`, `printenv`, `cat secrets/*`, `echo $SECRET_VAR`, and similar commands.

```bash
# In .bashrc on every machine:
[[ -f ~/dotfiles/bin/load-secrets.sh ]] && source ~/dotfiles/bin/load-secrets.sh
```

### Context Detection

`bin/detect-context.sh` scans the current directory for file signatures and exports `ACTIVE_CONTEXTS`:

| Signal       | File                                                   | Context        |
| ------------ | ------------------------------------------------------ | -------------- |
| Next.js      | `next.config.*`                                        | `nextjs`       |
| React Native | `"react-native"` in `package.json`                     | `react-native` |
| React        | `"react"` in `package.json` (if not Next/Native)       | `react`        |
| Node         | `package.json`                                         | `node`         |
| TypeScript   | `tsconfig.json`                                        | `typescript`   |
| PHP          | `composer.json`                                        | `php`          |
| Sanity       | `sanity.config.*`, `sanity.cli.*`                      | `sanity`       |
| Prisma       | `prisma/schema.prisma`                                 | `prisma`       |
| Docker       | `Dockerfile`, `docker-compose.*`                       | `docker`       |
| Python       | `requirements.txt`, `pyproject.toml`, `setup.py`, etc. | `python`       |
| Laravel      | `artisan`                                              | `laravel`      |

Agents read `ACTIVE_CONTEXTS` to decide which skills and instructions to load. The `.bashrc` integration re-runs detection on every `cd`.

### Skills

Skills are self-contained knowledge packages in `skills/`. Each has a `SKILL.md` that agents read when the skill's domain matches the task. Skills support self-learning — after completing a task, agents update the skill with lessons learned.

**Included skills:**

| Skill                    | Purpose                                                                                                                                                                                 |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `citation-builder-skill` | Automated local SEO citation building — browser form automation, Google Sheets tracking, email verification, NAP accuracy scoring. Full pipeline from domain list to verified listings. |
| `github-weekly-digest`   | Automated "what I shipped" pipeline — GitHub commits → per-repo AI analysis → narrative blog post → Sanity CMS draft. Three cadences: daily dev log, weekly post, rollup from daily files. Includes cron wrappers for VPS automation. |
| `portfolio-showcaser`    | Browser-driven portfolio analysis — code analysis, feature discovery, 4-axis scoring, dev server interaction, screenshot capture, and markdown+JSON report generation. 8-phase pipeline with resume support. |
| `skill-scaffolder`       | Meta-skill for creating new agent skills — generates complete skill directories with SKILL.md, scripts, config, and references following proven patterns. |
| `systematic-debugging`   | Root-cause-first debugging methodology — four-phase process (investigate → pattern analysis → hypothesis → implementation). Prevents guess-and-check thrashing.                         |

**Third-party skills** (installed via Copilot skill managers like `find-skills`) live in `~/.agents/skills/` and are symlinked into `~/.copilot/skills/` for VS Code discovery. These are not tracked in this repo — they update independently via their own package managers.

### Instruction Files

`CLAUDE.md` is the entry point. It always loads `global.instructions.md` first, then conditionally loads domain-specific files based on the workspace:

| File                             | Loads when       | What it enforces                                                                                                           |
| -------------------------------- | ---------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `global.instructions.md`         | Always           | DRY, no comments, early returns, strict validation, env-var-only secrets, skill self-learning rules, CSS/JS/DB conventions |
| `nextjs.instructions.md`         | Next.js project  | Next.js 16 / React 19 / TypeScript patterns — `"use cache"`, Server Actions, `useActionState`, Turbopack, proxy.ts         |
| `php.instructions.md`            | PHP project      | PHP 8.4+ strict OOP — typed constants, `#[Override]`, no traits, field visibility ordering                                 |
| `sanity.instructions.md`         | Sanity project   | Sanity MCP server reference — tool catalog, GROQ quick ref, document lifecycle, common workflows                           |
| `sentry.instructions.md`         | Sentry tasks     | Sentry MCP server reference — issue triage, error investigation, release correlation                                       |
| `google-docs.instructions.md`    | Google API tasks | Service account auth, Sheets/Docs/Slides/Drive API patterns, credential auto-discovery                                     |
| `codebase-audit.instructions.md` | Audit tasks      | Points to the audit prompt in `prompts/codebase-audit.txt`                                                                 |
| `exploration.instructions.md`    | "explore" tasks  | Codebase exploration, investigation, and architecture understanding methodology                                              |
| `technical-fellow.instructions.md`| "technical fellow" | Technical fellow role — ultra-specific implementation plans with action items, team roles, and checklists                  |
| `atomic-commits.md`              | "atomic commits" | Atomic commit workflow — one logical change per commit, stage carefully, conventional commit messages                        |

### Prompts

| Prompt | Purpose |
|---|---|
| `prompts/codebase-audit.txt` | Ruthless senior staff engineer code review — only real problems grouped by severity (critical, security, dead code, logic errors, race conditions, DRY violations, inconsistencies) |
| `prompts/technical-fellow.md` | Technical fellow planning template — ultra-specific implementation plans with action items, team roles, collaboration framework, and implementation checklists |

### Key VS Code Settings

`settings.json` configures ~220 settings. The most impactful:

| Setting                                               | Value                  | Why                                                  |
| ----------------------------------------------------- | ---------------------- | ---------------------------------------------------- |
| `chat.instructionsFilesLocations`                     | `{"~/dotfiles": true}` | Enables the entire instruction/skill discovery chain |
| `chat.agent.maxRequests`                              | `100000`               | Prevents agent from stopping mid-task                |
| `github.copilot.chat.anthropic.thinking.budgetTokens` | `32000`                | Extended thinking for complex reasoning              |
| `github.copilot.chat.responsesApiReasoningEffort`     | `xhigh`                | Maximum reasoning effort                             |
| `chat.exploreAgent.defaultModel`                      | `Claude Opus 4.6`      | Model selection for explore subagent                 |
| `claudeCode.allowDangerouslySkipPermissions`          | `true`                 | Claude Code auto-approve                             |

### Environment Variables

`.env.agent.example` and `.env.secrets.example` document all supported env vars:

| Group            | File          | Vars                                                                    | Used by                              |
| ---------------- | ------------- | ----------------------------------------------------------------------- | ------------------------------------ |
| System           | `.env.agent`  | `PYTHONUTF8`                                                            | All Python scripts                   |
| GitHub (config)  | `.env.agent`  | `GITHUB_USERNAME`                                                       | Git operations                       |
| GitHub (secret)  | `.env.secrets`| `GITHUB_PACKAGE_REGISTRY_TOKEN`                                         | Package publishing                   |
| OpenAI           | `.env.secrets`| `OPENAI_API_KEY`                                                        | AI skills, nanobot                   |
| Google Cloud     | `.env.agent`  | `GCP_CREDENTIALS_FILE`                                                  | Google Sheets/Docs/Drive API scripts |
| Citation (config)| `.env.agent`  | `CITATION_EMAIL`, `CITATION_SPREADSHEET_ID`, `CITATION_IMAP_HOST`, etc. | Citation campaign automation         |
| Citation (secret)| `.env.secrets`| `CITATION_VAULT_KEY`, `CITATION_EMAIL_PASSWORD`                         | Citation credential vault, IMAP auth |
| Anthropic        | `.env.secrets`| `ANTHROPIC_API_KEY`                                                     | GitHub digest AI analysis, narrative generation |
| GitHub (token)   | `.env.secrets`| `GITHUB_TOKEN`                                                          | GitHub digest repo/commit fetching |
| Sanity           | `.env.agent`  | `SANITY_PROJECT_ID`, `SANITY_DATASET`                                   | GitHub digest + portfolio CMS publishing |
| Sanity (secret)  | `.env.secrets`| `SANITY_TOKEN`                                                          | Sanity API write access |

## Prerequisites

- [VS Code Insiders](https://code.visualstudio.com/insiders/)
- [GitHub Copilot](https://github.com/features/copilot) subscription
- Git Bash (Windows) or bash (Linux/macOS)
- Python 3.10+ (for Google API scripts and citation builder)

## Installation

### Quick Setup (Recommended)

```bash
git clone https://github.com/arndvs/dotfiles.git ~/dotfiles
bash ~/dotfiles/bin/bootstrap.sh
```

The bootstrap script is idempotent (safe to re-run) and handles:

- Creating `secrets/.env.agent` and `secrets/.env.secrets` from templates
- Symlinking `~/.claude/CLAUDE.md` and `~/.claude/skills/`
- Wiring `load-secrets.sh` and `detect-context.sh` into `~/.bashrc`
- Creating the Python venv with base Google API packages

After running, fill in your config and secrets, then merge VS Code settings:

```bash
$EDITOR ~/dotfiles/secrets/.env.agent      # non-sensitive config (usernames, hosts, IDs)
$EDITOR ~/dotfiles/secrets/.env.secrets    # API keys, tokens, passwords
bash ~/dotfiles/bin/sync-settings.sh --dry-run   # preview changes
bash ~/dotfiles/bin/sync-settings.sh              # merge into VS Code Insiders
source ~/.bashrc
```

> On Windows, file symlinks require admin. The bootstrap copies `CLAUDE.md` instead and prints instructions for upgrading to a symlink. Directory symlinks (`~/.claude/skills/`) work without admin via Developer Mode.

### VPS Setup

Clone and bootstrap — same as local, but **do not run `sync-settings.sh` on the VPS**. VS Code Remote SSH forwards your local settings automatically.

```bash
git clone https://github.com/arndvs/dotfiles.git ~/dotfiles
bash ~/dotfiles/bin/bootstrap.sh
$EDITOR ~/dotfiles/secrets/.env.agent          # fill in non-sensitive config
$EDITOR ~/dotfiles/secrets/.env.secrets        # fill in API keys
source ~/.bashrc
```

Bootstrap runs a validation step at the end — all checks should pass. If any fail, re-read the error and re-run.

**What's different on VPS vs local:**

| Concern               | Local machine                               | VPS                                                      |
| --------------------- | ------------------------------------------- | -------------------------------------------------------- |
| VS Code settings      | Run `sync-settings.sh`                      | Forwarded via Remote SSH — do NOT run `sync-settings.sh` |
| `~/.claude/CLAUDE.md` | Symlink (or copy on Windows)                | Symlink                                                  |
| `secrets/.env.*`    | Your local API keys (split: agent + secrets) | Same keys or VPS-specific overrides                      |
| Python venv           | Created by bootstrap                        | Created by bootstrap                                     |
| Shell integration     | `.bashrc` / `.zshrc` (bootstrap wires both) | `.bashrc` / `.zshrc` (bootstrap wires both)              |

#### VPS Verification Checklist

After bootstrap, verify everything is wired correctly:

```bash
# Symlinks point to ~/dotfiles
readlink ~/.claude/CLAUDE.md        # should print /home/<user>/dotfiles/CLAUDE.md
readlink ~/.claude/skills           # should print /home/<user>/dotfiles/skills

# Secrets loaded
source ~/.bashrc
echo $GITHUB_USERNAME               # should print your username

# Context detection works
cd ~/some-project
echo $ACTIVE_CONTEXTS               # should list detected contexts
```

#### VPS Updating

```bash
cd ~/dotfiles && git pull
bash ~/dotfiles/bin/bootstrap.sh     # re-validates + fixes stale symlinks
source ~/.bashrc                     # pick up any new env vars
```

### Manual Setup

<details>
<summary>Step-by-step if you prefer not to use the bootstrap script</summary>

#### 1. Clone to ~/dotfiles

```bash
git clone https://github.com/arndvs/dotfiles.git ~/dotfiles
```

#### 2. Symlink CLAUDE.md

```bash
# macOS / Linux
mkdir -p ~/.claude
ln -sf ~/dotfiles/CLAUDE.md ~/.claude/CLAUDE.md
ln -sf ~/dotfiles/skills ~/.claude/skills

# Windows (Git Bash) — requires admin for file symlink
mkdir -p ~/.claude
ln -sf ~/dotfiles/skills ~/.claude/skills
cp ~/dotfiles/CLAUDE.md ~/.claude/CLAUDE.md
```

#### 3. Set Up Secrets

```bash
mkdir -p ~/dotfiles/secrets
cp ~/dotfiles/.env.agent.example ~/dotfiles/secrets/.env.agent
cp ~/dotfiles/.env.secrets.example ~/dotfiles/secrets/.env.secrets
# Edit .env.agent — fill in non-sensitive config (usernames, hosts, IDs)
# Edit .env.secrets — fill in API keys, tokens, passwords
```

#### 4. Wire Up Shell

Add to `~/.bashrc` (or `~/.zshrc`):

```bash
[[ -f ~/dotfiles/bin/load-secrets.sh ]] && source ~/dotfiles/bin/load-secrets.sh

_load_context() {
    [[ -f ~/dotfiles/bin/detect-context.sh ]] \
        && source ~/dotfiles/bin/detect-context.sh > /dev/null 2>&1
}
cd() { builtin cd "$@" && _load_context; }
_load_context
```

#### 5. Apply VS Code Settings

```bash
bash ~/dotfiles/bin/sync-settings.sh              # auto-merge
# Or manually: Ctrl+Shift+P → "Preferences: Open User Settings (JSON)" → merge
```

The critical setting that makes instruction discovery work:

```jsonc
"chat.instructionsFilesLocations": {
    "~/dotfiles": true,
    ".github/instructions": true
}
```

#### 6. Create Python venv

```bash
python3 -m venv ~/dotfiles/secrets/.venv
source ~/dotfiles/secrets/.venv/bin/activate   # Linux/macOS
# source ~/dotfiles/secrets/.venv/Scripts/activate  # Windows
pip install google-auth google-auth-httplib2 google-api-python-client
```

</details>

### Verify

```bash
# Quick validation of all env vars and file setup
bash ~/dotfiles/bin/validate-env.sh        # core vars only
bash ~/dotfiles/bin/validate-env.sh --all  # core + citation builder vars

# Check secrets are loaded
echo $GITHUB_USERNAME

# Check context detection
cd ~/your-nextjs-project
echo $ACTIVE_CONTEXTS  # should include "nextjs"

# In VS Code: open Copilot Chat in Agent mode
# Ask: "What instruction files do you see?"
```

## Scripts Reference

| Script                  | Purpose                                                           | Flags                   |
| ----------------------- | ----------------------------------------------------------------- | ----------------------- |
| `bin/bootstrap.sh`      | One-command machine setup — secrets, symlinks, shell, venv        | (none)                  |
| `bin/sync-settings.sh`  | Merge `settings.json` into VS Code user settings                  | `--dry-run`, `--stable` |
| `bin/load-secrets.sh`   | Source `secrets/.env.agent` (non-sensitive config) into shell      | (sourced, not run)      |
| `bin/run-with-secrets.sh`| Inject `secrets/.env.secrets` into a child process at runtime     | (wraps a command)       |
| `bin/detect-context.sh` | Detect project type, export `ACTIVE_CONTEXTS`                     | (sourced, not run)      |
| `bin/validate-env.sh`   | Validate env vars and hardening posture                           | `--all`                 |

`sync-settings.sh` details:

- Parses JSONC (strips `//` comments and trailing commas)
- Deep-merges: dotfiles keys override, user-only keys preserved
- Creates a timestamped backup before writing (e.g. `settings.backup-20260402-143000.json`)
- `--dry-run` — show what would change without writing
- `--stable` — target stable VS Code instead of Insiders

## Customization

- **Don't use PHP?** Delete `instructions/php.instructions.md` and remove its `@` reference from `CLAUDE.md`
- **Add a new stack?** Create `instructions/yourstack.instructions.md`, add a conditional `@` reference in `CLAUDE.md`, and add detection to `bin/detect-context.sh`
- **Add a skill?** Create `skills/your-skill/SKILL.md` — VS Code discovers it automatically via the `instructionsFilesLocations` setting
- **New config?** Add the key to `.env.agent.example`, add the value to `secrets/.env.agent`
- **New secrets?** Add the key to `.env.secrets.example`, add the value to `secrets/.env.secrets`
- **Sync VS Code settings?** Run `bash ~/dotfiles/bin/sync-settings.sh --dry-run` to preview, then without `--dry-run` to apply

## Updating

```bash
cd ~/dotfiles && git pull
bash ~/dotfiles/bin/bootstrap.sh        # re-validates symlinks, creates missing files
bash ~/dotfiles/bin/sync-settings.sh    # merge any new VS Code settings (LOCAL only)
source ~/.bashrc                        # pick up any new env vars
```

On a VPS, skip `sync-settings.sh` — VS Code Remote SSH forwards settings from your local machine.

> **Note:** If your git remote still shows `ai-files.git` (the old repo name), update it:
>
> ```bash
> git remote set-url origin https://github.com/arndvs/dotfiles.git
> ```

## Troubleshooting

**Instructions not loading in Copilot Chat**

- Verify the symlink: `readlink ~/.claude/CLAUDE.md` — should point to `~/dotfiles/CLAUDE.md`
- If it's a regular file (not a symlink), re-run `bash ~/dotfiles/bin/bootstrap.sh`
- Check that `chat.instructionsFilesLocations` includes `"~/dotfiles": true` in your VS Code settings

**`secrets/.env.agent not found` warning on shell startup**

- Run: `cp ~/dotfiles/.env.agent.example ~/dotfiles/secrets/.env.agent`
- Fill in non-sensitive config: `$EDITOR ~/dotfiles/secrets/.env.agent`
- Run: `cp ~/dotfiles/.env.secrets.example ~/dotfiles/secrets/.env.secrets`
- Fill in API keys and tokens: `$EDITOR ~/dotfiles/secrets/.env.secrets`

**`sync-settings.sh` fails on VPS**

- This is expected — `sync-settings.sh` only works on your local machine
- VS Code Remote SSH forwards your local settings to the VPS automatically

**`ACTIVE_CONTEXTS` not set / empty**

- Verify `.bashrc` has the context-detection block: `grep "detect-context" ~/.bashrc`
- If missing, re-run `bash ~/dotfiles/bin/bootstrap.sh`
- Context detection runs on `cd` — it reads the current directory's files

**Python venv missing or broken**

- Delete and recreate: `rm -rf ~/dotfiles/secrets/.venv && bash ~/dotfiles/bin/bootstrap.sh`

## Architecture Decisions

| Decision                             | Rationale                                                                                                                                                                   |
| ------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `~/dotfiles` path hardcoded          | Every script, instruction, and shell snippet uses `~/dotfiles`. This is the contract — don't rename.                                                                        |
| Secrets gitignored, template tracked | `secrets/` never leaves the machine. `.env.agent.example` and `.env.secrets.example` are the schemas.                                                                              |
| Skills in repo, not `~/.agents/`     | Third-party skill managers update `~/.agents/skills/` independently. Our custom skills live in `~/dotfiles/skills/` so they're version-controlled and sync across machines. |
| Python venv inside `secrets/`        | The venv is machine-specific (different OS, Python version) and gitignored alongside secrets. Rebuilt per-machine by `bootstrap.sh`.                                        |
| JSONC settings, not JSON             | VS Code `settings.json` uses JSONC (comments, trailing commas). `sync-settings.sh` handles this with a Python JSONC parser.                                                 |
| Copy not symlink on Windows          | Windows file symlinks require admin. Directory symlinks work via Developer Mode. Bootstrap falls back to copy for files and warns.                                          |
