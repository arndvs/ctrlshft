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
│   └── codebase-audit.instructions.md  Audit methodology
├── skills/                     ← custom skills (auto-discovered by VS Code)
│   ├── citation-builder-skill/     automated SEO citation building pipeline
│   └── systematic-debugging/       root-cause-first debugging methodology
├── prompts/                    ← reusable prompt templates
│   └── codebase-audit.txt          ruthless audit prompt
├── bin/                        ← shell scripts sourced in .bashrc
│   ├── load-secrets.sh             sources secrets/.env into shell (cross-platform)
│   ├── detect-context.sh           auto-detects project type → ACTIVE_CONTEXTS
│   ├── bootstrap.sh                one-command setup for a fresh machine
│   └── sync-settings.sh            merge VS Code settings from dotfiles
├── secrets/                    ← GITIGNORED — per-machine secrets
│   ├── .env                        master env vars (from .env.example)
│   ├── .env.citation               citation-specific env vars
│   ├── *.json                      GCP service account credentials
│   └── .venv/                      shared Python venv for Google API scripts
├── working/                    ← GITIGNORED — scratch files, migration scripts
└── .env.example                ← template for secrets/.env (tracked in git)
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

Secrets never live in code. The resolution chain:

1. `secrets/.env` sourced into shell by `bin/load-secrets.sh` (added to `.bashrc`)
2. Scripts read from `os.environ` / `process.env` / `$VAR`
3. Fallback: `GCP_CREDENTIALS_FILE` env var → auto-discover from `secrets/*.json`
4. If missing → hard error naming the var and pointing to `.env.example`

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

### Prompts

`prompts/codebase-audit.txt` — a reusable audit prompt for a "ruthless senior staff engineer" code review. Reports only real problems grouped by severity (critical, security, dead code, logic errors, race conditions, DRY violations, inconsistencies). No filler.

### Key VS Code Settings

`settings.json` configures ~220 settings. The most impactful:

| Setting                                               | Value                  | Why                                                  |
| ----------------------------------------------------- | ---------------------- | ---------------------------------------------------- |
| `chat.instructionsFilesLocations`                     | `{"~/dotfiles": true}` | Enables the entire instruction/skill discovery chain |
| `chat.agent.maxRequests`                              | `100000`               | Prevents agent from stopping mid-task                |
| `github.copilot.chat.anthropic.thinking.budgetTokens` | `32000`                | Extended thinking for complex reasoning              |
| `github.copilot.chat.responsesApiReasoningEffort`     | `xhigh`                | Maximum reasoning effort                             |
| `chat.exploreAgent.defaultModel`                      | `Claude Opus 4.6`      | Model selection for explore subagent                 |
| `remote.SSH.remotePlatform`                           | `{"vps": "linux"}`     | VPS target for Remote SSH                            |
| `claudeCode.allowDangerouslySkipPermissions`          | `true`                 | Claude Code auto-approve                             |

### Environment Variables

`.env.example` documents all supported env vars. Key groups:

| Group            | Vars                                                                    | Used by                              |
| ---------------- | ----------------------------------------------------------------------- | ------------------------------------ |
| System           | `PYTHONUTF8`                                                            | All Python scripts                   |
| GitHub           | `GITHUB_USERNAME`, `GITHUB_PACKAGE_REGISTRY_TOKEN`                      | Git operations, package publishing   |
| OpenAI           | `OPENAI_API_KEY`                                                        | AI skills, nanobot                   |
| Google Cloud     | `GCP_CREDENTIALS_FILE`                                                  | Google Sheets/Docs/Drive API scripts |
| Citation Builder | `CITATION_VAULT_KEY`, `CITATION_EMAIL`, `CITATION_SPREADSHEET_ID`, etc. | Citation campaign automation         |

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

- Creating `secrets/.env` from the template
- Symlinking `~/.claude/CLAUDE.md` and `~/.claude/skills/`
- Wiring `load-secrets.sh` and `detect-context.sh` into `~/.bashrc`
- Creating the Python venv with base Google API packages

After running, fill in your secrets and merge VS Code settings:

```bash
$EDITOR ~/dotfiles/secrets/.env
bash ~/dotfiles/bin/sync-settings.sh --dry-run   # preview changes
bash ~/dotfiles/bin/sync-settings.sh              # merge into VS Code Insiders
source ~/.bashrc
```

> On Windows, file symlinks require admin. The bootstrap copies `CLAUDE.md` instead and prints instructions for upgrading to a symlink. Directory symlinks (`~/.claude/skills/`) work without admin via Developer Mode.

### VPS Setup

Same steps — clone and bootstrap:

```bash
git clone https://github.com/arndvs/dotfiles.git ~/dotfiles
bash ~/dotfiles/bin/bootstrap.sh
# Fill in secrets/.env with the same keys (or VPS-specific values)
```

When you connect via VS Code Remote SSH, the `chat.instructionsFilesLocations` setting is forwarded — the remote VS Code server discovers `~/dotfiles` on the VPS and loads the same instructions and skills.

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
cp ~/dotfiles/.env.example ~/dotfiles/secrets/.env
# Edit secrets/.env — fill in your API keys
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
# Check secrets are loaded
echo $GITHUB_USERNAME

# Check context detection
cd ~/your-nextjs-project
echo $ACTIVE_CONTEXTS  # should include "nextjs"

# In VS Code: open Copilot Chat in Agent mode
# Ask: "What instruction files do you see?"
```

## Scripts Reference

| Script                  | Purpose                                                    | Flags                   |
| ----------------------- | ---------------------------------------------------------- | ----------------------- |
| `bin/bootstrap.sh`      | One-command machine setup — secrets, symlinks, shell, venv | (none)                  |
| `bin/sync-settings.sh`  | Merge `settings.json` into VS Code user settings           | `--dry-run`, `--stable` |
| `bin/load-secrets.sh`   | Source `secrets/.env` into current shell                   | (sourced, not run)      |
| `bin/detect-context.sh` | Detect project type, export `ACTIVE_CONTEXTS`              | (sourced, not run)      |

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
- **New secrets?** Add the key name to `.env.example`, add the value to `secrets/.env`
- **Sync VS Code settings?** Run `bash ~/dotfiles/bin/sync-settings.sh --dry-run` to preview, then without `--dry-run` to apply

## Updating

```bash
cd ~/dotfiles && git pull
bash ~/dotfiles/bin/sync-settings.sh   # merge any new VS Code settings
source ~/.bashrc                        # pick up any new env vars
```

## Architecture Decisions

| Decision                             | Rationale                                                                                                                                                                   |
| ------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `~/dotfiles` path hardcoded          | Every script, instruction, and shell snippet uses `~/dotfiles`. This is the contract — don't rename.                                                                        |
| Secrets gitignored, template tracked | `secrets/` never leaves the machine. `.env.example` is the schema.                                                                                                          |
| Skills in repo, not `~/.agents/`     | Third-party skill managers update `~/.agents/skills/` independently. Our custom skills live in `~/dotfiles/skills/` so they're version-controlled and sync across machines. |
| Python venv inside `secrets/`        | The venv is machine-specific (different OS, Python version) and gitignored alongside secrets. Rebuilt per-machine by `bootstrap.sh`.                                        |
| JSONC settings, not JSON             | VS Code `settings.json` uses JSONC (comments, trailing commas). `sync-settings.sh` handles this with a Python JSONC parser.                                                 |
| Copy not symlink on Windows          | Windows file symlinks require admin. Directory symlinks work via Developer Mode. Bootstrap falls back to copy for files and warns.                                          |
