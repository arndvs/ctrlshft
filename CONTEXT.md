# Project Context

Agent-facing context for working in the ctrl+shft repository.

## What This Repo Is

ctrl+shft is a dotfiles framework for AI coding agents. It provides:

- **ctrl** — instructions, skills, rules, secrets, context detection
- **shft** — autonomous agent loop (picks GitHub issues, implements, commits, repeats)

The on-disk path is `~/dotfiles`. The GitHub repo is `arndvs/ctrlshft`.

## Repository Structure

| Directory        | Purpose                                           |
| ---------------- | ------------------------------------------------- |
| `bin/`           | CLI tools (`ctrl` entrypoint, bootstrap, helpers) |
| `shft/`          | Autonomous loop (`afk.sh`, `once.sh`, engine)     |
| `skills/`        | Agent workflow skills (SKILL.md per skill)         |
| `rules/`         | Path-gated coding conventions                     |
| `agents/`        | Subagent persona definitions                      |
| `commands/`      | Slash command dispatchers                         |
| `hooks/`         | Claude Code lifecycle hooks                       |
| `instructions/`  | Stack-specific instruction files                  |
| `docs/`          | Architecture docs, ADRs                           |
| `secrets/`       | Gitignored credentials (3-tier model)             |
| `working/`       | Gitignored runtime state and plans                |

## Key Files

- `CLAUDE.base.md` — edit this, bootstrap generates `CLAUDE.md` from it
- `global.instructions.md` — always-loaded agent rules
- `bin/bootstrap.sh` — one-command idempotent setup
- `bin/detect-context.sh` — stack detection (exports `ACTIVE_CONTEXTS`)
- `REPO_TOPOLOGY.md` — private/public remote split documentation

## Conventions

- Shell scripts source `bin/_lib.sh` for shared utilities
- Skills follow `skills/<name>/SKILL.md` structure
- Rules use `paths:` YAML frontmatter for file-glob scoping
- Instructions use `<context>.instructions.md` naming
- All secrets go through `secrets/` (never hardcoded)
- `working/` is for cross-conversation plans (disposable)

## Development Workflow

1. All development happens on feature branches off `dev`
2. PRs target `dev` (never `main` directly)
3. Issues live in the public repo (`arndvs/ctrlshft`)
4. Run `ctrl check` before committing
5. See `REPO_TOPOLOGY.md` for the private/public remote split
