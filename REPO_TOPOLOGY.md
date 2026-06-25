# Repository Topology

This document describes the maintainer topology for keeping Aaron's private dotfiles and the public ctrl+shft project aligned. Public users do not need Aaron's private remote; they should use the normal GitHub fork flow for `arndvs/ctrlshft`.

## Operating phases

| Phase | Where work starts | Why |
| --- | --- | --- |
| Cleanup/staging | `dotfiles-private` | Containment, secret-adjacent cleanup, remote guardrails, and public-promotion planning stay private until validated. |
| Steady state | `ctrlshft` for core/product work; `dotfiles-private` for personal overlay | Public product work should build public history first, then be pulled back into the private checkout for Aaron's machine-specific configuration. |

Until final readiness is approved, use `dotfiles-private` as the staging area and promote only sanitized ranges to `ctrlshft`. After cleanup, default new Sandcastle, shft, hooks, skills, and docs work to public `ctrlshft` unless it is personal, secret-adjacent, local-machine-specific, or part of a private containment workflow.

## Canonical roles

| Name | URL | Role |
| --- | --- | --- |
| `~/dotfiles` | local path | Private working checkout and source of truth for this machine |
| `origin` | private GitHub repo | Maintainer-only canonical remote for real dotfiles and personal overlay work |
| `public` | `https://github.com/arndvs/ctrlshft.git` | Public/sanitized ctrl+shft project repository |

Do not use `upstream` for `arndvs/ctrlshft` in the private checkout. In this repo, `upstream` reads like "canonical source", but the current cleanup-phase canonical source is private `origin`. Public forks may use the conventional `origin` = fork and `upstream` = `arndvs/ctrlshft`; that public-fork topology is separate from this maintainer checkout.

## Push policy

- Push normal dotfiles work to `origin`.
- Treat `public` as fetch-only by default.
- Public pushes must be intentional, sanitized, and explicitly allowed with `CTRL_ALLOW_PUBLIC_PUSH=1`.
- Even intentional public pushes run `bin/validate-public-promotion.sh` to block private-only runtime paths, local config, unsafe installed workflows, and unsanitized content.
- Before promoting commit history, run `bin/preflight-public-promotion.sh --range <public-base>..HEAD` to validate only the candidate commits and exclude containment work.
- `remote.pushDefault` must be unset or set to `origin`; it must never point at `public` or `upstream`.

## Steady-state sync workflow

After cleanup and final readiness:

1. Start public-safe product work in `ctrlshft` so public history is native and reviewable.
2. Pull or merge accepted public changes back into `dotfiles-private`.
3. Keep private overlay changes, local machine configuration, secrets, working state, and emergency containment work only in `dotfiles-private`.
4. If private work later becomes product work, create a sanitized promotion branch from the public base and validate it before pushing.

This makes `ctrlshft` the durable public product history while `dotfiles-private` remains Aaron's private integration checkout.

## Public promotion guardrails

Sandcastle is intended to become public ctrl+shft product code, including the installed `.sandcastle/**` tree after sanitization. The promotion guard scans `.sandcastle/**` for private repo/local-machine references and high-confidence secret-like values before public push.

Do not promote these private-only paths directly to `ctrlshft`:

- `sandcastle.config.json`
- `.github/workflows/agent-*.yml`
- `working/active/**`, `working/runtime/**`, `working/tmp/**`, `working/logs/**`, `working/refs/**`, `working/research/**`
- non-example `secrets/**` and local `.env*` files

Intentional Sandcastle productization belongs in `.sandcastle/**` plus source paths such as `shft/templates/`, `shft/engine/`, `shft/docs/`, `bin/*sandcastle*.sh`, and `test/sandcastle-*.sh`.

## Sandcastle public promotion plan

Do not promote the private `dev` branch to public `main` directly. The raw private-to-public history includes private-only installed workflow files, local Sandcastle install config, and emergency-containment/token-hardening subjects that the range preflight intentionally blocks.

Promote Sandcastle from a dedicated public promotion branch based on `public/main`:

1. Fetch the public base and create a promotion branch from it: `git fetch public main && git switch -c promote/sandcastle public/main`.
2. Preserve public-safe source history by replaying commits for `shft/engine/**`, `shft/templates/**`, `shft/docs/**`, `bin/init-sandcastle.sh`, `bin/update-sandcastle.sh`, `bin/preflight-sandcastle.sh`, and `test/sandcastle-*.sh` when each commit passes `bin/preflight-public-promotion.sh`.
3. Rewrite or squash commits whose content is public-safe but whose original subject/path history is not. In the current Sandcastle history this includes token-name workflow fixes and dogfood commits that touched installed `.github/workflows/agent-*.yml` or `sandcastle.config.json`.
4. Add `.sandcastle/**` as a sanitized installed-runtime snapshot from the reviewed source tree instead of replaying the dogfood `.sandcastle` history. The final `.sandcastle/**` tree is promotable, but its private dogfood history is not the public product history.
5. Exclude `sandcastle.config.json` and installed `.github/workflows/agent-*.yml`; public consumers should get workflow templates from `shft/templates/workflows/` and generate installed workflows intentionally.
6. Before any public push, run `bash bin/validate-public-promotion.sh` and `bash bin/preflight-public-promotion.sh --range public/main..HEAD` on the exact promotion branch. Push only through `bin/preflight-public-promotion.sh --push --confirm-public-push`.

This keeps the public repository current with Sandcastle product work while preserving safe source history and avoiding publication of private dotfiles runtime state.

## Issue ownership

| Work type | Issue home |
| --- | --- |
| Private dotfiles, personal workflow, secrets-adjacent changes | `arndvs/dotfiles-private` |
| Public product work and sanitized ctrl+shft docs/features | `arndvs/ctrlshft` |
| Work that starts private and later becomes public | Start private, then open/link a public issue or PR when sanitized |

## Historical note

This project was originally called `ctrlshft` while also serving as the real private dotfiles repo. That private instance was briefly published publicly. The current split is intentional:

- `dotfiles-private` is the private cleanup/staging area and long-term personal overlay.
- `ctrlshft` is the public/sanitized project and steady-state home for core product work.

Run `bash ~/dotfiles/bin/validate-remotes.sh` after clone, branch changes, or remote changes to confirm the topology is safe. In a private checkout it enforces the maintainer remote layout above. In a public/fork checkout it skips private remote requirements and only checks for private remote URL references in tracked content.