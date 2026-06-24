# Coding Standards

These standards apply when Sandcastle agents work in ctrl+shft repositories.

## General

- Treat the repository checkout as the source of truth for agent configuration.
- Do not edit generated consumer paths such as `~/.claude/`, `~/.copilot/`, or `~/.agents/` directly.
- Keep changes lean, atomic, and tied to the issue being worked.
- Prefer explicit failures with context over silent fallbacks.
- Do not hardcode or print secrets. Use environment variables and repo secrets only.
- Respect repository topology and never push private overlays or local runtime state to public repositories.

## Shell

- Use `set -euo pipefail` in executable shell scripts.
- Source `bin/_lib.sh` for shared output helpers when writing `bin/` scripts.
- Quote variables and prefer `[[ ... ]]` tests.
- Avoid long inline heredocs in terminal-driven automation; write temp scripts/files instead.

## TypeScript

- Keep TypeScript strict and explicit at module boundaries.
- Use Zod schemas for structured agent output validation.
- Preserve the retry/extraction split:
	- `runWithRetry()` for side-effect-free structured output.
	- `runWithExtraction()` when the first run has side effects and only extraction should be retried.
- Paginate every GitHub list API call. Use `gh api --paginate` for REST and GraphQL cursor loops for connection fields.

## Sandcastle vendoring

- Source files live under `shft/`; consumer files under `.sandcastle/` are stamped copies.
- Run `ctrl update-sandcastle --dry-run` after changing `shft/engine`, `shft/templates`, or Sandcastle workflow templates.
- Do not vendor tests, `node_modules`, or local lockfiles into `.sandcastle/engine` commits unless the installer/updater explicitly supports them.

## Testing

- For `shft/engine`, run `npx vitest run` and `npx tsc --noEmit`.
- For shell script edits, run `bash -n` on changed scripts.
- Validate generated Sandcastle files with `ctrl update-sandcastle --dry-run`.
