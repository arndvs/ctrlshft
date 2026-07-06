# Repository Topology

This document describes the maintainer topology for keeping Aaron's private dotfiles and the public ctrl+shft project aligned. Public users do not need Aaron's private remote; they should use the normal GitHub fork flow for `arndvs/ctrlshft`.

## Operating model

`ctrlshft` is the canonical public product repository for Sandcastle, shft,
hooks, skills, docs, and other reusable automation. Start public-safe product
work here so review and history are native to the public project, then pull
accepted changes back into `dotfiles-private` for Aaron's machine-specific
overlay.

Keep personal configuration, secrets, local runtime state, and private
containment work in `dotfiles-private`.

## Canonical roles

| Name | URL | Role |
| --- | --- | --- |
| `ctrlshft` | `https://github.com/arndvs/ctrlshft.git` | Public canonical repository for reusable product work |
| `dotfiles-private` | private GitHub repo | Maintainer-only overlay for real dotfiles, secrets-adjacent work, and machine-specific integration |
| `~/dotfiles` | local path | Aaron's private working checkout, usually synced from public plus private overlay changes |

In a public checkout, use the normal GitHub fork topology (`origin` = your fork,
`upstream` = `arndvs/ctrlshft`) if needed. In Aaron's private checkout, remote
names may differ, but public-safe product changes still flow through
`arndvs/ctrlshft` before being pulled back into the private overlay.

## Push policy

- Push reusable product work to `ctrlshft` through feature branches and PRs.
- Keep private overlay work in `dotfiles-private`.
- Public pushes from a private checkout must be intentional, sanitized, and explicitly allowed with `CTRL_ALLOW_PUBLIC_PUSH=1`.
- Even intentional public pushes run `bin/validate-public-promotion.sh` to block private runtime paths, local environment files, private secret paths, and unsanitized content.
- Before promoting commit history, run `bin/preflight-public-promotion.sh --range <public-base>..HEAD` to validate only the candidate commits and exclude containment work.
- In a private checkout, `remote.pushDefault` must not point at the public remote unless the push path is intentionally guarded.

## Steady-state sync workflow

1. Start public-safe product work in `ctrlshft` so public history is native and reviewable.
2. Pull or merge accepted public changes back into `dotfiles-private`.
3. Keep private overlay changes, local machine configuration, secrets, working state, and emergency containment work only in `dotfiles-private`.
4. If private work later becomes product work, create a sanitized promotion branch from the public base and validate it before pushing.

This makes `ctrlshft` the durable public product history while `dotfiles-private` remains Aaron's private integration checkout.

## Public promotion guardrails

Sandcastle is public ctrl+shft product code, including the installed
`.sandcastle/**` tree after sanitization. The promotion guard scans
`.sandcastle/**` for private repo/local-machine references and high-confidence
secret-like values before public push.

Do not promote these private-only paths directly to `ctrlshft`:

- `working/active/**`, `working/runtime/**`, `working/tmp/**`, `working/logs/**`, `working/refs/**`, `working/research/**`
- non-example `secrets/**` and local `.env*` files except the tracked
  template allowlist: `.env.agent.example`, `.env.secrets.example`,
  `.env.citation.example`, `secrets/.env.agent.example`, and
  `secrets/.env.bridge.example`

Host-managed Sandcastle files such as `sandcastle.config.json` and installed
`.github/workflows/agent-*.yml` / `.github/workflows/agent-*.yaml` workflows
are allowed in this repository. They are still subject to content scanning and
review like any other public file.

Intentional Sandcastle productization belongs in `.sandcastle/**`, host-managed
workflow/config files, and source paths such as `shft/templates/`,
`shft/engine/`, `shft/docs/`, `bin/*sandcastle*.sh`, and
`test/sandcastle-*.sh`.

## Public promotion checks

Use the guard scripts before pushing or promoting public history:

1. Run `bash bin/validate-public-promotion.sh` to validate the tracked tree.
2. Run `bash bin/preflight-public-promotion.sh --range <base>..HEAD` before
   promoting a candidate range.
3. Push public branches only after the tree and range checks pass.

The checks allow host-managed Sandcastle config/workflows, and continue to block
private runtime state, local env files, private secret paths, high-confidence
secret-like values, emergency-containment commit subjects, and private
`.sandcastle` references.

## Issue ownership

| Work type | Issue home |
| --- | --- |
| Private dotfiles, personal workflow, secrets-adjacent changes | `arndvs/dotfiles-private` |
| Public product work and sanitized ctrl+shft docs/features | `arndvs/ctrlshft` |
| Work that starts private and later becomes public | Start private, then open/link a public issue or PR when sanitized |

## Historical note

This project was originally called `ctrlshft` while also serving as the real private dotfiles repo. That private instance was briefly published publicly. The current split is intentional:

- `dotfiles-private` is the private personal overlay and machine integration checkout.
- `ctrlshft` is the public project and steady-state home for core product work.

Run `bash ~/dotfiles/bin/validate-remotes.sh` after clone, branch changes, or remote changes to confirm the topology is safe. In a private checkout it enforces the maintainer remote layout above. In a public/fork checkout it skips private remote requirements and only checks for private remote URL references in tracked content.