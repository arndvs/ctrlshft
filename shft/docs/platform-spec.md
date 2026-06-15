# Platform Spec

Sandcastle is an autonomous agent pipeline that turns GitHub issues into merged PRs using a label-driven state machine.

## Architecture

```
GitHub Issue
  ↓ (Sandcastle label applied)
agent:review → agent:implement → agent:pr-open
  ↓                                              ↓
agent:blocked (human input needed)           agent:review (PR)
                                                 ↓
                                          agent:fix (if feedback)
                                                 ↓
                                          agent:merge
```

### Components

| Layer | Location | Purpose |
|-------|----------|---------|
| **Engine** | `shft/engine/` | TypeScript library — workflows, schemas, lib helpers |
| **Templates** | `shft/templates/` | Workflow YAMLs, prompts, extractions, hooks, scripts |
| **CLI** | `bin/init-sandcastle.sh` | Scaffolds Sandcastle in any repo |
| **Updater** | `bin/update-sandcastle.sh` | Syncs vendored engine + templates with drift detection |

### Engine internals

- **`lib/`** — Shared utilities: shell helpers, config loader, prompt resolver, diff parser, retry/extraction wrappers, PR comment fetcher, thread resolver, scoring, semaphore
- **`workflows/`** — One runner per workflow: review, implement-pr, to-issues-prd, update-branch, architecture-review, implement-issue, merge-pr
- **`schemas/`** — Zod schemas for structured output from each workflow

### Retry strategy

Two wrappers handle structured output extraction failures:

| Wrapper | Use when | Behavior |
|---------|----------|----------|
| `runWithRetry()` | Output IS the work (no side effects) | Retries the same session with feedback |
| `runWithExtraction()` | Work has side effects (commits) | Produce phase (no output), then extract phase with retries |

Both resume the existing Sandcastle session rather than re-running from scratch.
For `runWithExtraction()` workflows, produce prompts do the side-effecting work only; extraction prompts own all structured-output instructions.

## Workflow YAMLs

GitHub Actions workflows in `shft/templates/workflows/`:

The full dogfood smoke-test contract for these workflows lives in `shft/docs/full-smoke-matrix.md`.

| File | Trigger | Purpose |
|------|---------|---------|
| `agent-review-issue.yml` | `Sandcastle` label | Reviews issue context and advances to `agent:review` |
| `agent-plan-issue.yml` | `agent:review` label | Breaks issue into sub-tasks |
| `agent-implement-issue.yml` | `agent:implement` label | Implements issue, opens PR |
| `agent-implement-prd.yml` | `agent:implement-prd` label | Implements next sub-issue of a PRD |
| `agent-fix-pr-feedback.yml` | `agent:fix` label | Addresses PR review comments |
| `agent-architecture-review.yml` | Schedule + `workflow_dispatch` | Full architecture review |
| `agent-merge-pr.yml` | `agent:merge` label | Merges PR after checks pass |
| `agent-update-branch.yml` | `agent:update-branch` label | Rebases/merges branch against base |
| `agent-check-stale-prs.yml` | Schedule | Finds stale PRs needing attention |
| `agent-promote-queued.yml` | Issue closed | Unblocks queued issues when dependencies close |

Workflow files under `shft/templates/workflows/` are source templates, not copy-paste-ready installed workflows. `init-sandcastle.sh` stamps `{{DEFAULT_BRANCH}}` and `{{PACKAGE_MANAGER}}` into `.github/workflows/agent-*.yml`; publishing or installing raw templates without that substitution produces broken workflows.

### Workflow security contract

`agent-fix-pr-feedback.yml`, `agent-merge-pr.yml`, and `agent-update-branch.yml` use `pull_request_target` so they can update labels and same-repository PR branches. Their fork protections are a required security pair:

- keep the `refuse-fork` job that removes the triggering label, adds `agent:blocked`, and comments on fork PRs
- keep the main mutation job guarded by `github.event.pull_request.head.repo.full_name == github.repository`

Do not remove either side of that pair. Without both checks, a public repository could run privileged agent steps against untrusted fork code.

## Prompt templates

Located in `shft/templates/prompts/`. Each workflow resolves its prompt via `resolvePrompt()` which checks:
1. Repo-local override in `{config.promptDir}/{name}.md`
2. Default template in `shft/templates/prompts/{name}.md`

Extraction prompts (for two-phase workflows) live in `shft/templates/extractions/`.

## Configuration

`sandcastle.config.json` in the consumer repo root:

```json
{
  "model": "claude-opus-4-6",
  "baseBranch": "main",
  "sandbox": "none",
  "promptDir": ".sandcastle/prompts",
  "codingStandards": ".sandcastle/CODING_STANDARDS.md",
  "contextDoc": "CONTEXT.md",
  "adrDir": "docs/adr",
  "packageManager": "pnpm"
}
```

Only `sandbox: "none"` is currently supported by the TypeScript engine. Docker and worktree sandbox modes are intentionally rejected until provider wiring and CI validation are implemented.

## Required GitHub Actions secrets

Sandcastle expects these repository secrets after `ctrl init-sandcastle`:

| Secret | Required for | Notes |
|--------|--------------|-------|
| `CLAUDE_CODE_OAUTH_TOKEN` | Workflows that invoke Claude Code (`implement-issue`, `implement-prd`, `write-pr`, `architecture-review`) | Authenticates Claude Code in GitHub Actions. Configure it alongside the LiteLLM proxy secrets; it is not a replacement for them. |
| `LITELLM_BASE_URL` | All model-backed workflows | Claude-compatible proxy endpoint used through `ANTHROPIC_BASE_URL`. |
| `LITELLM_MASTER_KEY` | All model-backed workflows | Proxy auth token used through `ANTHROPIC_AUTH_TOKEN`. |
| `AGENT_PAT` | Workflow-to-workflow label handoffs and reliable branch/PR mutations | Required for the label-driven state machine because `GITHUB_TOKEN` label changes do not trigger follow-up workflow runs. Use a classic PAT with `repo` scope for private repositories, or equivalent fine-grained issue/PR/content scopes. |

## Vendoring model

Consumer repos don't install Sandcastle engine as a dependency — `init-sandcastle.sh` copies the engine source into `.sandcastle/engine/` and `update-sandcastle.sh` syncs it with drift detection. This keeps the pipeline self-contained and version-pinned per repo.

The vendored engine is a runtime scaffold, not a source checkout. Test files are excluded, so `init-sandcastle.sh` and `update-sandcastle.sh` render `.sandcastle/engine/package.json` with a no-op `test` script while preserving `typecheck` for validating vendored runtime sources.

## Engine package and lockfile policy

`shft/engine/package.json` is the public product package for the Sandcastle engine. It should be promoted with:

| Field | Public policy |
|-------|---------------|
| `packageManager` | Keep the declared `pnpm@10.33.2` package manager so installs and lockfile updates are reproducible. |
| `dependencies` | Keep `@anthropic-ai/claude-code`, `@ai-hero/sandcastle`, and `zod`; these are runtime requirements for GitHub Actions workflows and the engine's structured output validation. |
| `devDependencies` | Keep TypeScript, `tsx`, Node types, and `vitest`; tests and local typechecking run from the source package, not the vendored runtime package. |
| `scripts.test` | Keep `vitest run` in `shft/engine/package.json`. Render a no-op `test` script only in `.sandcastle/engine/package.json` because vendored runtime installs intentionally omit `*.test.ts` files. |
| `pnpm.onlyBuiltDependencies` | Keep the explicit build allowlist for packages that need install-time native/binary setup. |
| `pnpm-lock.yaml` | Track and promote the lockfile with the source package and vendored runtime snapshot. Do not regenerate it with another package manager. |

The only intentional source-to-vendored package drift is the rendered no-op `test` script in `.sandcastle/engine/package.json`. Dependency versions, package-manager declaration, TypeScript configuration, and lockfile content should otherwise match the source engine package.

For the current private-to-public Sandcastle promotion, the private `shft/engine/package.json` changes are public-safe and should be recreated or replayed in ctrl+shft:

| Current public drift | Decision |
|----------------------|----------|
| Missing `packageManager` and lockfile | Promote `pnpm@10.33.2` and `pnpm-lock.yaml`; package-manager drift is not intentional. |
| `@ai-hero/sandcastle` behind the private source version | Promote the private source version with the matching lockfile. |
| Missing `@anthropic-ai/claude-code` | Promote it; workflow runners invoke Claude Code in GitHub Actions and this is product behavior, not private dogfood state. |
| Missing `vitest` and `test` script | Promote them in `shft/engine` so source tests are runnable; keep only the rendered no-op test script in `.sandcastle/engine`. |
| `start` still pointing at the legacy `main.ts` runner | Promote the dispatcher-oriented `start` script because workflow runners now execute via `.sandcastle/run.ts`. |

No package dependency is private-only by itself. Private dogfood assumptions live in `sandcastle.config.json`, installed `.github/workflows/agent-*.yml`, repository secrets, and local runtime state; those remain excluded from public promotion.

## Public promotion shape

The public ctrl+shft repository should carry both Sandcastle source and the sanitized installed runtime:

| Path | Public role | Promotion rule |
|------|-------------|----------------|
| `shft/engine/**` | Product source for the TypeScript engine | Preserve safe commit history where `preflight-public-promotion.sh` passes. |
| `shft/templates/**` | Product source for workflows, prompts, scripts, hooks, and setup templates | Preserve safe commit history; promote installed workflow behavior as templates, not as `.github/workflows/agent-*.yml`. |
| `shft/docs/**` | Public product documentation | Preserve safe commit history. |
| `bin/*sandcastle*.sh`, `test/sandcastle-*.sh` | Public CLI/update/preflight and smoke-test tooling | Preserve safe commit history after private wording is sanitized. |
| `.sandcastle/**` | Sanitized generated runtime snapshot for dogfooding and public inspection | Add from the reviewed final tree as a snapshot; do not replay private dogfood runtime history. |

Private install state stays private. Do not publish `sandcastle.config.json`, installed `.github/workflows/agent-*.yml`, working/runtime artifacts, local env files, or secret values. Validate the exact promotion branch with `bin/validate-public-promotion.sh` and `bin/preflight-public-promotion.sh --range public/main..HEAD` before pushing to public.
