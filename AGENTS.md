# AGENTS.md — ctrlshft (public)

`ctrlshft` is the **primary, authoritative product source** for Sandcastle, shft,
hooks, skills, docs, and reusable automation. Public work starts HERE so review
and history are native to the public project.

## Canonical invariants

Read `~/dotfiles/WORKSPACE_INVARIANTS.md` for the full ownership test, private-only
list, and guard index. Run `ctrl prime "<scope>"` before cross-root or
file-writing tasks.

## What this repo owns (branch 1 of the ownership test)

- `shft/templates/workflows/**` — product workflow templates (mirror of hub)
- `shft/templates/actions/**`, `shft/templates/prompts/**`, `shft/templates/extractions/**`
- `shft/engine/**` — engine source (publishes to `sandcastle-hub`)
- `test/**`, `docs/adr/**`, `plans/**`, `bin/**`
- `REPO_TOPOLOGY.md` — canonical topology doc

Resolve these here, then pull back to dotfiles (Direction A in
`~/dotfiles/seams/public-pullback.md`).

## What it does NOT own (never)

- Private/`dotfiles` overlay paths: `secrets/`, `working/`, `.env*`
- `skills/_local/**`, `instructions/_local/**`
- `sandcastle.config.json` + installed `.github/workflows/agent-*.yml` —
  host-managed consumer assets, never promoted FROM private
- `llm-gateway` — runtime, unrelated to product CI

## Push policy

- Work on `dev`, PR to `main`. Never push `dev→main` directly.
- Public pushes require `CTRL_ALLOW_PUBLIC_PUSH=1` AND passing
  `bin/validate-public-promotion.sh` + `bin/preflight-public-promotion.sh --range`.
- The `main` branch accepts only `dev`-headed promotion PRs
  (validate-main-pr-source).

## Hub relationship

Engine + canonical templates live in `arndvs/sandcastle-hub`. Changes to engine
or templates go hub-first (edit hub, run `test/hub-smoke-coverage.sh`, mirror
back via `bin/sync-hub-templates.sh`). See `~/dotfiles/seams/vendor-sandcastle.md`.