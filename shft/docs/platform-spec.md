# Sandcastle Platform Specification

Sandcastle is a label-driven autonomous agent platform built on GitHub Actions. It turns GitHub issues into working code through a pipeline of AI agent workflows, orchestrated by labels and cron schedules.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        GitHub Repository                        │
│                                                                 │
│  Issues ──label──> Actions ──engine──> Branches ──PR──> Merged  │
│                                                                 │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────────────┐│
│  │ labels.json  │   │  Workflows   │   │    .sandcastle/      ││
│  │ (state       │   │  (.github/   │   │    ├─ run.ts         ││
│  │  machine     │   │   workflows/ │   │    ├─ prompts/       ││
│  │  definition) │   │   agent-*.yml│   │    ├─ extractions/   ││
│  │              │   │  )           │   │    ├─ hooks/         ││
│  └──────────────┘   └──────────────┘   │    ├─ scripts/       ││
│                                        │    ├─ sandbox/       ││
│                                        │    └─ labels.json    ││
│                                        └──────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │  Sandcastle      │
                    │  Engine          │
                    │  (@ai-hero/      │
                    │   sandcastle)    │
                    │                  │
                    │  main.ts         │
                    │  ├─ lib/         │
                    │  ├─ workflows/   │
                    │  └─ schemas/     │
                    └──────────────────┘
```

## Core Concepts

### Label-Driven State Machine

Labels applied to GitHub issues and PRs are the sole triggers for agent workflows. Each label maps to exactly one GitHub Actions workflow file. When a label is applied, the corresponding workflow fires, the engine runs the appropriate workflow function, and the result is posted back to GitHub (as commits, comments, PR reviews, or new issues).

See [triage-labels.md](triage-labels.md) for the full label inventory and state transitions.

### Separation of Thinking and Acting

The engine enforces a strict boundary between AI reasoning and side effects:

1. **Thinking** — The AI agent runs inside a sandbox, reads the codebase, and emits structured JSON output (validated by Zod schemas).
2. **Acting** — TypeScript code in `lib/` and `workflows/` receives the validated output and performs side effects: posting reviews via the GitHub API, creating issues, resolving threads, committing code.

This separation means the agent never directly calls the GitHub API. It describes *what* to do; the engine *does* it.

### Structured Output Validation

Every workflow defines a Zod schema for its expected agent output. The engine uses `@ai-hero/sandcastle`'s `Output.object()` to extract and validate the agent's response. If the output doesn't match the schema, a `StructuredOutputError` is thrown with the raw output for debugging.

Schema field aliasing via Zod `.transform()` handles common LLM output variations (e.g., `file`/`path`, `body`/`comment`).

## Engine Workflows

### Issue Workflows

| Workflow | Registry name | Trigger | Purpose |
|----------|--------------|---------|---------|
| Plan | `to-issues-prd` | `agent:plan` label | Decomposes a PRD issue into sub-issues with acceptance criteria and dependency order |
| Review Issue | `review-issue` | `agent:review` label | Reviews an issue for clarity, feasibility, and completeness |
| Implement Issue | `implement-issue` | `agent:implement` label | Implements a single issue end-to-end (branch, code, commit, PR) |
| Implement PRD | `implement-prd` | `agent:implement-prd` label | Implements all slices of a PRD sequentially |
| Architecture Review | `architecture-review` | `agent:architecture-review` label | Scoped architecture review of the codebase |

### PR Workflows

| Workflow | Registry name | Trigger | Purpose |
|----------|--------------|---------|---------|
| Address Review | `address-review` | `agent:auto-fix` label + review submitted | Scores review comments, applies fixes, resolves threads |
| Merge | — (Actions-only) | `agent:merge` label | Squash-merges PR when checks pass (via `gh pr merge`, no engine) |
| Review | `review` | Direct invocation | Posts a code review with inline comments and summary |
| Implement PR | `implement-pr` | Direct invocation | Addresses specific PR review feedback |
| Write PR | `write-pr` | Direct invocation | Creates a PR from a completed branch |
| Update Branch | `update-branch` | `agent:update-branch` label | Rebases or merges base branch into PR branch |

### Orchestration Workflows

| Workflow | Registry name | Trigger | Purpose |
|----------|--------------|---------|---------|
| Parallel | `parallel` | `agent-promote-queued.yml` (cron) or direct | Fan-out concurrent implementation of multiple issues |

## Agent Pipeline

### Single-Issue Flow

```
Label applied ─> GitHub Actions ─> Engine CLI
                                      │
                                      ▼
                                   Checkout repo
                                      │
                                      ▼
                              Load sandcastle.config.json
                                      │
                                      ▼
                              Resolve prompt template
                                      │
                                      ▼
                              Create sandbox (branch)
                                      │
                                      ▼
                              Run agent with prompt + schema
                                      │
                                      ▼
                              Validate structured output (Zod)
                                      │
                                      ▼
                              Execute side effects (GitHub API, git)
                                      │
                                      ▼
                              Post summary / close issue / open PR
```

### Parallel Flow

```
Cron trigger (every 4h) ─> agent-promote-queued.yml
                                │
                                ▼
                          Find issues labeled "queued"
                                │
                                ▼
                          Plan phase: select + prioritize issues
                                │
                                ▼
                          ┌─────┼─────┬─────┐
                          ▼     ▼     ▼     ▼
                       Issue  Issue  Issue  Issue   (Semaphore-gated,
                        #1     #2     #3     #4      max-parallel=4)
                          │     │     │     │
                          ▼     ▼     ▼     ▼
                       Branch Branch Branch Branch
                          │     │     │     │
                          ▼     ▼     ▼     ▼
                       Implement (Claude Code agent per branch)
                          │     │     │     │
                          └─────┼─────┴─────┘
                                │
                                ▼
                          Merge phase: merge completed branches
                                │
                                ▼
                          Report: merged[], failed[], testsPassed
```

### Review Feedback Loop

```
PR opened ──────────────────────────> Code review submitted
                                           │
                                           ▼
                                    agent-fix-pr-feedback.yml
                                           │
                                           ▼
                                    Score each comment (0-100)
                                           │
                              ┌────────────┼────────────┐
                              ▼            ▼            ▼
                         Auto (≥75)   Confirm (40-74)  HITL (<40)
                         Apply fix    Apply fix +      Create issue
                         Resolve      await confirm    Link in thread
                              │            │
                              ▼            ▼
                         Re-request Copilot review
                              │
                              ▼
                         Next round (up to maxReviewRounds)
                              │
                              ▼ (cap reached)
                         Label: review-cap-reached
                         Post summary of remaining threads
```

## Comment Scoring

The engine scores review comments to decide whether to auto-fix, seek confirmation, or defer to a human.

**Base score:** 50

**Positive signals** (+20 each):
Missing `await`, null pointer, race condition, SQL injection, XSS, memory leak, off-by-one, undefined reference, type error, wrong return type, unused import/variable, dead code, missing error handling, security vulnerability, breaking change.

**Negative signals** (-20 each):
"consider", "you might want", "nitpick", style preference, minor suggestion, "optional", "just a thought", "food for thought", personal preference, refactoring suggestion, cosmetic, formatting, whitespace.

**Modifiers:**
- Code block in comment: +10 (suggests a concrete fix)
- Very short comment (<30 chars): -10 (likely drive-by)
- References a specific line: +5

**Tier thresholds** (configurable in `sandcastle.config.json`):
- **Auto** (≥75): Apply the fix and resolve the thread automatically.
- **Confirm** (40-74): Apply the fix but await human confirmation.
- **HITL** (<40): Create a GitHub issue and link it in the review thread.

## Configuration

`sandcastle.config.json` at the repo root:

```json
{
  "defaultBranch": "main",
  "model": "claude-sonnet-4-20250514",
  "maxIterations": 1,
  "maxParallel": 4,
  "maxIssues": 5,
  "sandbox": "none",
  "maxReviewRounds": 3,
  "scoreThresholds": {
    "auto": 75,
    "confirm": 40
  }
}
```

All fields have defaults and can be overridden with environment variables:

| Config key | Env var | Default |
|-----------|---------|---------|
| `defaultBranch` | `SANDCASTLE_DEFAULT_BRANCH` | `main` |
| `model` | `SANDCASTLE_MODEL` | `claude-sonnet-4-20250514` |
| `maxIterations` | `SANDCASTLE_MAX_ITERATIONS` | `1` |
| `maxParallel` | `SANDCASTLE_MAX_PARALLEL` | `4` |
| `maxIssues` | `SANDCASTLE_MAX_ISSUES` | `5` |
| `promptsDir` | `SANDCASTLE_PROMPTS_DIR` | (auto-resolved) |
| `sandbox` | `SANDCASTLE_SANDBOX` | `none` |
| `maxReviewRounds` | `SANDCASTLE_MAX_REVIEW_ROUNDS` | `3` |

## Installation

Sandcastle is installed into a target repository using the `init-sandcastle` CLI:

```bash
ctrl init-sandcastle [TARGET_DIR] [--sandbox none|docker]
```

This scaffolds:

1. `.sandcastle/` — Engine source, prompts, extractions, hooks, scripts, sandbox config
2. `.github/workflows/agent-*.yml` — Workflow files with `{{DEFAULT_BRANCH}}` replaced
3. `.github/copilot-setup-steps.yml` — Copilot agent setup
4. `sandcastle.config.json` — Project configuration
5. GitHub labels from `labels.json` (via `gh label create`)

Updates are applied with `ctrl update-sandcastle [--dry-run]`, which diffs the installed files against the current templates and patches selectively.

## Templates

The `shft/templates/` directory is the source of truth for all installable files:

| Directory | Contents |
|-----------|----------|
| `prompts/` | Markdown prompt templates for each workflow (plan, implement, review, etc.) |
| `extractions/` | Structured output extraction templates |
| `workflows/` | GitHub Actions workflow YAML files (use `{{DEFAULT_BRANCH}}` token) |
| `hooks/` | Pre-commit hooks (e.g., `block-npx-tsc.sh`) |
| `scripts/` | Utility scripts (token checker, secrets setup) |
| `sandbox/` | Docker sandbox Dockerfile and docs |
| `labels.json` | Label definitions for the state machine |
| `copilot-setup-steps.yml` | GitHub Copilot agent setup steps |
| `run.ts` | Vendored dispatcher entrypoint copied into `.sandcastle/` |

## Validation

The engine validates agent outputs at multiple levels:

- **Schema validation:** Zod schemas reject malformed structured output with `StructuredOutputError`
- **Diff validation:** Inline review comments are checked against `git diff` — comments on lines not in the diff are silently dropped with a warning
- **Thread validation:** Reply `commentId`s are validated against fetched PR threads — invalid IDs are dropped with a warning
- **Token verification:** `scripts/check-file-tokens.sh` ensures no `{{DEFAULT_BRANCH}}` tokens remain after installation
