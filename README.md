# AI Files

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
│   └── detect-context.sh           auto-detects project type → ACTIVE_CONTEXTS
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

| Signal | File | Context |
|--------|------|---------|
| Next.js | `next.config.*` | `nextjs` |
| Sanity | `sanity.config.*` | `sanity` |
| PHP | `composer.json` | `php` |
| Prisma | `prisma/schema.prisma` | `prisma` |
| Python | `requirements.txt`, `pyproject.toml` | `python` |
| Docker | `Dockerfile`, `docker-compose.*` | `docker` |

Agents read `ACTIVE_CONTEXTS` to decide which skills and instructions to load. The `.bashrc` integration re-runs detection on every `cd`.

### Skills

Skills are self-contained knowledge packages in `skills/`. Each has a `SKILL.md` that agents read when the skill's domain matches the task. Skills support self-learning — after completing a task, agents update the skill with lessons learned.

Third-party skills (installed via skill managers) live in `~/.agents/skills/` and are symlinked into `~/.copilot/skills/` for VS Code discovery.

## Prerequisites

- [VS Code Insiders](https://code.visualstudio.com/insiders/)
- [GitHub Copilot](https://github.com/features/copilot) subscription
- Git Bash (Windows) or bash (Linux/macOS)
- Python 3.10+ (for Google API scripts and citation builder)

## Installation

### 1. Clone to ~/dotfiles

```bash
# Any OS
git clone https://github.com/kangarko/ai-files.git ~/dotfiles
```

### 2. Symlink CLAUDE.md

Symlink (not copy) so edits to the source propagate automatically:

```bash
# macOS / Linux
mkdir -p ~/.claude
ln -sf ~/dotfiles/CLAUDE.md ~/.claude/CLAUDE.md

# Windows (Git Bash, run as admin)
mkdir -p ~/.claude
ln -sf ~/dotfiles/CLAUDE.md ~/.claude/CLAUDE.md
```

### 3. Set Up Secrets

```bash
cp ~/dotfiles/.env.example ~/dotfiles/secrets/.env
# Edit secrets/.env — fill in your API keys, tokens, credentials
```

### 4. Wire Up Shell

Add to `~/.bashrc` (or `~/.zshrc`):

```bash
# Secrets
[[ -f ~/dotfiles/bin/load-secrets.sh ]] && source ~/dotfiles/bin/load-secrets.sh

# Context detection (re-runs on cd)
_load_context() {
    [[ -f ~/dotfiles/bin/detect-context.sh ]] \
        && source ~/dotfiles/bin/detect-context.sh > /dev/null 2>&1
}
cd() { builtin cd "$@" && _load_context; }
_load_context
```

### 5. Apply VS Code Settings

1. `Cmd+Shift+P` (macOS) or `Ctrl+Shift+P` (Windows/Linux)
2. **"Preferences: Open User Settings (JSON)"**
3. Merge `settings.json` from this repo into your user settings

The critical setting that makes instruction discovery work:

```jsonc
"chat.instructionsFilesLocations": {
    "~/dotfiles": true,
    ".github/instructions": true
}
```

### 6. VPS Setup

On a Linux VPS accessed via VS Code Remote SSH:

```bash
git clone https://github.com/kangarko/ai-files.git ~/dotfiles
cp ~/dotfiles/.env.example ~/dotfiles/secrets/.env
# Fill in secrets/.env with the same keys (or VPS-specific values)

# Add to ~/.bashrc
echo '[[ -f ~/dotfiles/bin/load-secrets.sh ]] && source ~/dotfiles/bin/load-secrets.sh' >> ~/.bashrc

# Python venv for Google API scripts
python3 -m venv ~/dotfiles/secrets/.venv
source ~/dotfiles/secrets/.venv/bin/activate
pip install google-auth google-auth-httplib2 google-api-python-client
```

When you connect via VS Code Remote SSH, the `chat.instructionsFilesLocations` setting is forwarded — the remote VS Code server discovers `~/dotfiles` on the VPS and loads the same instructions and skills.

### 7. Verify

```bash
# Check secrets are loaded
echo $GITHUB_USERNAME

# Check context detection
cd ~/your-nextjs-project
echo $ACTIVE_CONTEXTS  # should include "nextjs"

# In VS Code: open Copilot Chat in Agent mode
# Ask: "What instruction files do you see?"
```

## Customization

- **Don't use PHP?** Delete `instructions/php.instructions.md` and remove its `@` reference from `CLAUDE.md`
- **Add a new stack?** Create `instructions/yourstack.instructions.md`, add a conditional `@` reference in `CLAUDE.md`, and add detection to `bin/detect-context.sh`
- **Add a skill?** Create `skills/your-skill/SKILL.md` — VS Code discovers it automatically via the `instructionsFilesLocations` setting
- **New secrets?** Add the key name to `.env.example`, add the value to `secrets/.env`

## Updating

```bash
cd ~/dotfiles && git pull
# Run on every machine — instructions, skills, and scripts update in place
```
