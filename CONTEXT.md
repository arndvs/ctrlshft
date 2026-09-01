# ctrl+shft Context

`ctrl+shft` is Aaron's dotfiles-backed operating system for agent-assisted work. This public repo is the canonical source for reusable shell tools, prompts, rules, skills, Sandcastle templates, and automation.

## Source of truth

- Public-safe product work starts in `arndvs/ctrlshft`.
- Generated consumer locations such as `~/.claude/`, `~/.copilot/`, and `~/.agents/` must not be edited directly.
- Aaron's private `~/dotfiles/` checkout pulls from public and carries only personal overlay, local-machine, and secrets-adjacent work.
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

This repo is a Sandcastle consumer under the hub model. The engine is NOT
vendored — it runs from `arndvs/ctrlshft-hub` via the `agent-run` composite
action. `.sandcastle/` holds only a `hub-version.json` SHA-lock (plus local
prompt overrides); the engine is referenced remotely, never copied in.

- `.sandcastle/hub-version.json` pins the hub ref/SHA; the `sandcastle-drift`
  workflow opens a review PR when the hub advances.
- Project-specific files are `sandcastle.config.json` and `.sandcastle/prompts/` overrides.
- Default branch for dogfood workflows is `dev`.
- Required GitHub Actions secrets are `LITELLM_BASE_URL` and `LITELLM_MASTER_KEY`; `AGENT_PAT` is recommended for label-driven workflow chaining.

## Working expectations

- Keep changes small and atomic.
- Run relevant tests before committing.
- Preserve secret safety: do not print or commit credential values.
- Prefer removing or simplifying code over adding abstractions.
- If a command mutates GitHub labels, issues, PRs, or secrets, be explicit about the repo target.