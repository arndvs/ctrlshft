## Problem Statement

The AFK Agent Platform ("Sandcastle") currently lives in two places — `.sandcastle/` in `course-video-manager` (the original, project-coupled prototype) and `shft/engine/` in `~/dotfiles` (a partially-extracted generalization). This creates active code drift between duplicated infrastructure (`parse-diff-lines.ts`, output schemas, retry wrappers) and leaves no automated way to stamp the CI layer (8 GitHub Actions workflow YAMLs) into new repos. Onboarding a new repo to the platform requires manually copying ~30 files, creating 8 labels, adding secrets, and writing project-specific prompts — with no mechanism to detect or fix drift afterward.

## Solution

Consolidate `shft/engine/` as the single source of shared Sandcastle infrastructure, create a template system for workflow YAMLs and prompt skeletons, and build a `ctrl init-sandcastle` CLI command that scaffolds a complete Sandcastle setup in any repo. A companion `ctrl update-sandcastle` command detects drift and offers patches. Per-repo customization happens through `sandcastle.config.ts` (model, base branch, sandbox strategy, paths) and prompt overrides in `.sandcastle/prompts/`, while all shared TypeScript runners, schemas, and utilities live in `~/dotfiles/shft/engine/`.

## User Stories

1. As a developer, I want to run `ctrl init-sandcastle` in any repo, so that I get a fully working AFK agent pipeline without manually copying files.
2. As a developer, I want per-repo configuration via `sandcastle.config.ts`, so that I can customize model, base branch, and sandbox strategy without editing shared code.
3. As a developer, I want prompt templates with override support, so that I can customize agent behavior per-project while inheriting sensible defaults.
4. As a developer, I want `ctrl update-sandcastle` to detect workflow YAML drift, so that I know when a repo's CI layer is out of date with the latest platform.
5. As a developer, I want all shared TypeScript infrastructure (retry wrappers, diff parsers, output schemas) in one canonical location, so that bug fixes propagate to all repos.
6. As a developer, I want GitHub labels auto-created during init, so that I don't have to manually create 8 labels in every new repo.
7. As a developer, I want the workflow runners to read config instead of hardcoding values, so that `claude-opus-4-6`, `main`, and `npm` aren't baked into every runner.
8. As a developer, I want the deprecated RALPH loop (`main.ts`, `plan-prompt.md`, `implement-prompt.md`, `review-prompt.md`, `merge-prompt.md`) cleaned up, so that new adopters aren't confused by two orchestration models.
9. As a developer, I want workflow YAML templates that are 100% repo-agnostic, so that copying them verbatim to any repo works without edits (except default branch name).
10. As a developer, I want a `copilot-setup-steps.yml` template, so that GitHub Copilot coding agent can work in repos that adopt the platform.
11. As a developer, I want `course-video-manager` migrated to consume from dotfiles, so that it validates the extraction and stops carrying duplicated infrastructure.
12. As a developer, I want the init command to be idempotent and safe for existing repos (refuse to overwrite without `--force`), so that I can't accidentally destroy project-specific customizations.

## Implementation Decisions

### Architecture: Stamp-and-own with drift detection

Workflow YAMLs and engine code are **copied** into each repo at init time — the repo owns its copy. `ctrl update-sandcastle` detects drift and offers patches. This beats git submodules (fragile in CI, merge conflicts), reusable GitHub Actions (trigger restrictions, secret-passing limitations), and npm packages (can't install workflow YAMLs).

### Config schema: `sandcastle.config.ts`

A Zod-validated config file in each repo root:
```ts
export default {
  model: "claude-opus-4-6",        // LLM model for all runners
  baseBranch: "main",              // default branch name
  sandbox: "none",                 // "none" | "docker" | "worktree"
  promptDir: ".sandcastle/prompts", // prompt override directory
  codingStandards: ".sandcastle/CODING_STANDARDS.md",
  contextDoc: "CONTEXT.md",
  adrDir: "docs/adr",
  packageManager: "pnpm",          // "npm" | "pnpm" | "yarn" | "bun"
}
```

Runners call `loadConfig()` which reads this file and fills defaults for missing fields. Missing config file = all defaults.

### Prompt template system

Default prompts live in `~/dotfiles/shft/templates/prompts/`. Project-specific overrides live in `.sandcastle/prompts/`. Runners resolve prompts by checking the override directory first, falling back to templates. Template variables (`{{CONTEXT_DOC}}`, `{{ADR_DIR}}`, `{{CODING_STANDARDS}}`) are resolved from config at runtime.

### Shared infrastructure consolidation

These files from `course-video-manager/.sandcastle/` move to `~/dotfiles/shft/engine/lib/`:
- `run-with-retry.ts` + tests
- `run-with-extraction.ts` + tests
- `retry-feedback.ts`
- `parse-diff-lines.ts` + tests (already exists in both locations — merge and deduplicate)

Output schemas consolidate into `~/dotfiles/shft/engine/schemas/`.

### Workflow YAML templates

All 8 workflow YAMLs from `course-video-manager/.github/workflows/` are already 100% repo-agnostic (use `${{ github.repository }}`). The only hardcoded value is `main` as the default branch — templates use `{{DEFAULT_BRANCH}}` which `ctrl init-sandcastle` resolves via sed.

### CI vendoring strategy

In GitHub Actions CI, `~/dotfiles` isn't available. The engine code is vendored into `.sandcastle/engine/` at init time. `ctrl update-sandcastle` refreshes the vendored copy. Each repo's `.sandcastle/run.ts` is the single entry point that dispatches to the vendored runners.

### RALPH loop deprecation

`main.ts` (plan→implement→review→merge loop), `plan-prompt.md`, `implement-prompt.md`, `review-prompt.md`, `merge-prompt.md`, and `<promise>COMPLETE</promise>` conventions are removed from the shared platform. The standalone CI-triggered workflows supersede this.

### New directory structure in dotfiles

```
~/dotfiles/shft/
├── engine/
│   ├── lib/              ← ALL shared TS infrastructure
│   │   ├── config.ts     ← loadConfig() + Zod schema
│   │   ├── run-with-retry.ts
│   │   ├── run-with-extraction.ts
│   │   ├── retry-feedback.ts
│   │   ├── parse-diff-lines.ts
│   │   ├── fetch-pr-comments.ts
│   │   └── semaphore.ts
│   ├── schemas/          ← Zod output schemas
│   ├── workflows/        ← all workflow runners
│   └── package.json
└── templates/
    ├── workflows/        ← 8 YAML templates
    ├── prompts/          ← default prompt skeletons
    ├── copilot-setup-steps.yml
    ├── labels.json       ← label definitions
    └── CODING_STANDARDS.template.md
```

### Per-repo structure after init

```
<repo>/
├── .github/workflows/agent-*.yml  ← stamped from templates
├── .sandcastle/
│   ├── engine/                    ← vendored from dotfiles
│   ├── prompts/                   ← project-specific overrides
│   ├── run.ts                     ← dispatcher entry point
│   ├── sandcastle.config.ts       ← project config
│   └── CODING_STANDARDS.md        ← project-specific
├── CONTEXT.md
└── docs/adr/
```

### CLI commands

- `ctrl init-sandcastle [--branch main] [--model claude-opus-4-6] [--pm pnpm] [--force]`
- `ctrl update-sandcastle` — checksums vendored engine + workflow YAMLs vs dotfiles, shows diffs, prompts for update

## Testing Decisions

- Unit tests for `loadConfig()` — default resolution, partial overrides, missing file handling
- Unit tests for template variable resolution in prompt loader
- Unit tests for shared infrastructure (already exist: `run-with-retry.test.ts`, `run-with-extraction.test.ts`, `parse-diff-lines.test.ts`)
- Integration test: `ctrl init-sandcastle` in a scratch directory produces valid structure
- End-to-end validation: create test issue in `course-video-manager` after migration, verify full pipeline

## Out of Scope

- We are not building an npm package for the shared infrastructure — direct file vendoring is simpler and avoids publish/version overhead.
- We are not using GitHub reusable workflows (`workflow_call`) — trigger restrictions and secret-passing limitations make this impractical for `pull_request_target`-based workflows.
- We are not using git submodules for `.sandcastle/` — submodule update friction and CI fragility outweigh the benefits.
- We are not automating `ctrl update-sandcastle` via CI (e.g., Dependabot-style PRs) — drift detection is manual for now.
- We are not migrating repos other than `course-video-manager` in this PRD — they come after validation.
- We are not changing the label state machine (`agent:implement`, `agent:review`, etc.) — it stays as-is.

## Further Notes

- **Two orchestration models coexist**: The RALPH loop (`main.ts`) and the standalone CI workflows. This PRD deprecates the RALPH loop in the shared platform. `course-video-manager` may keep its copy temporarily during migration.
- **`shft/engine/` already has partial overlap**: `workflows/review.ts`, `workflows/implement-pr.ts`, `workflows/to-issues-prd.ts`, `lib/parse-diff-lines.ts`, `lib/fetch-pr-comments.ts` already exist. Consolidation means merging the better version from each location, not starting from scratch.
- **Windows compatibility**: `ctrl init-sandcastle` must work on Windows (Git Bash) since that's the primary dev environment. File copies, not symlinks, for vendored engine code.
- **`AGENT_PAT` cascade**: Labels added via `GITHUB_TOKEN` don't trigger downstream workflows. The `agent:implement` → `agent:review` chain depends on `AGENT_PAT`. The init command must document this clearly in its output checklist.
