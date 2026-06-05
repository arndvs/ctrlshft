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

## Workflow YAMLs

GitHub Actions workflows in `shft/templates/workflows/`:

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
  "packageManager": "npm"
}
```

## Vendoring model

Consumer repos don't install Sandcastle engine as a dependency — `init-sandcastle.sh` copies the engine source into `.sandcastle/engine/` and `update-sandcastle.sh` syncs it with drift detection. This keeps the pipeline self-contained and version-pinned per repo.
