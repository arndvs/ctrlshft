# Repository Topology

This checkout is the private source checkout for Aaron's real dotfiles.

## Canonical roles

| Name | URL | Role |
| --- | --- | --- |
| `~/dotfiles` | local path | Private working checkout and source of truth for this machine |
| `origin` | `https://github.com/arndvs/dotfiles-private.git` | Private canonical remote for real dotfiles work |
| `public` | `https://github.com/arndvs/ctrlshft.git` | Public/sanitized ctrl+shft project repository |

Do not use `upstream` for `arndvs/ctrlshft` in this checkout. In this repo, `upstream` reads like "canonical source", but the canonical source is private `origin`.

## Push policy

- Push normal dotfiles work to `origin`.
- Treat `public` as fetch-only by default.
- Public pushes must be intentional, sanitized, and explicitly allowed with `CTRL_ALLOW_PUBLIC_PUSH=1`.
- `remote.pushDefault` must be unset or set to `origin`; it must never point at `public` or `upstream`.

## Issue ownership

| Work type | Issue home |
| --- | --- |
| Private dotfiles, personal workflow, secrets-adjacent changes | `arndvs/dotfiles-private` |
| Public product work and sanitized ctrl+shft docs/features | `arndvs/ctrlshft` |
| Work that starts private and later becomes public | Start private, then open/link a public issue or PR when sanitized |

## Historical note

This project was originally called `ctrlshft` while also serving as the real private dotfiles repo. That private instance was briefly published publicly. The current split is intentional:

- `dotfiles-private` is the private source of truth.
- `ctrlshft` is the public/sanitized project.

Run `bash ~/dotfiles/bin/validate-remotes.sh` after clone, branch changes, or remote changes to confirm the topology is safe.