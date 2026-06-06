# Repository Topology

This document describes the private/public repository split for ctrl+shft.

## Remotes

| Remote   | Repository                | Role                                         |
| -------- | ------------------------- | -------------------------------------------- |
| `origin` | `arndvs/dotfiles-private` | Private canonical repo — all development     |
| `public` | `arndvs/ctrlshft`         | Public open-source mirror — curated releases |

> **Public clone users** (forks of `arndvs/ctrlshft`) have a single `origin` pointing to their fork. The `public` remote only exists in the private repo.

## Push Policy

| Remote   | Push allowed?                                                        |
| -------- | -------------------------------------------------------------------- |
| `origin` | Yes — normal development workflow                                    |
| `public` | **Gated** — requires `CTRL_ALLOW_PUBLIC_PUSH=1` environment variable |

The pre-push hook blocks pushes to any remote URL containing `ctrlshft` unless the gate variable is set. This prevents accidental publication of private content.

```bash
# Intentional public push (after verifying content is safe):
CTRL_ALLOW_PUBLIC_PUSH=1 git push public main
```

## Issue Ownership

All issues live in the **public** repo (`arndvs/ctrlshft`). The private repo has no issue tracker enabled. PRDs, slices, and QA issues all target the public repo.

## What Gets Published

### Publish (public-safe)

- `shft/` — framework source (engine lib, workflows, schemas, templates, docs)
- `bin/` — CLI tools and infrastructure scripts
- `skills/`, `rules/`, `agents/`, `commands/`, `hooks/` — agent configuration
- `instructions/` — stack-specific instructions (excluding `_local/`)
- `docs/` — architecture, ADRs, plans
- Infrastructure files (`README.md`, `CLAUDE.base.md`, `.github/`)

### DO NOT Publish

- `.sandcastle/` — vendored dogfood instance (installed copy of Sandcastle)
- `.github/workflows/agent-*.yml` — installed workflow copies with hardcoded branches
- `sandcastle.config.json` — project-specific Sandcastle config
- `secrets/` — credentials and environment files
- `working/` — runtime state, active plans
- `skills/_local/`, `instructions/_local/` — private skills and instructions

## Validation

Run `bin/validate-remotes.sh` to verify remote topology is correct:

```bash
bash bin/validate-remotes.sh
```

This checks:
- Remote URLs match expected patterns
- Push URL for `public` is disabled (private repo only)
- `pushDefault` is set to `origin` (private repo only)
- No `dotfiles-private` push URLs leak into tracked files
