# ctrl+shft Context

`ctrl+shft` is Aaron's dotfiles-backed operating system for agent-assisted work. This private repo is the canonical source for shell tools, prompts, rules, skills, Sandcastle templates, and local automation.

## Source of truth

- `~/dotfiles/` is authoritative.
- Generated consumer locations such as `~/.claude/`, `~/.copilot/`, and `~/.agents/` must not be edited directly.
- Public publishing goes through the sanitized `public` remote (`arndvs/ctrlshft`); private work stays on `origin` (`arndvs/dotfiles-private`).
- `REPO_TOPOLOGY.md` defines remote behavior and must be respected before push/publish changes.

## Important areas

- `bin/` — user-facing shell commands, including `ctrl`, bootstrap, validation, HUD, bridge, and Sandcastle install/update commands.
- `shft/` — AFK work execution, Sandcastle engine, templates, workflows, prompts, and docs.
- `skills/` and `instructions/` — source files for agent customization. Private/local variants live under `_local/` and are ignored.
- `rules/` — reusable instruction files copied into consumer targets.
- `bridge/` — GitHub/Copilot review bridge services.
- `hud/` and `bin/hud-daemon.js` — local dashboard/event loop.
- `working/` — tracked planning documents plus local runtime state. Do not commit sensitive values or machine-only logs.
- `secrets/` — ignored credential/config area. Never read secret values directly; use environment variables and wrappers.

## Sandcastle dogfood

This repo is the first Sandcastle consumer. `.sandcastle/` is intentionally vendored from `shft/` so GitHub Actions can run without depending on a local dotfiles checkout.

- Use `ctrl update-sandcastle --dry-run` to detect drift between `.sandcastle/` and `shft/`.
- Project-specific files are `sandcastle.config.json`, `.sandcastle/CODING_STANDARDS.md`, and `.sandcastle/prompts/` overrides.
- Default branch for dogfood workflows is `dev`.
- Required GitHub Actions secrets are `CLAUDE_CODE_OAUTH_TOKEN` and `ANTHROPIC_API_KEY`; `AGENT_PAT` is recommended for label-driven workflow chaining.

## Working expectations

- Keep changes small and atomic.
- Run relevant tests before committing.
- Preserve secret safety: do not print or commit credential values.
- Prefer removing or simplifying code over adding abstractions.
- If a command mutates GitHub labels, issues, PRs, or secrets, be explicit about the repo target.