# shft

The autonomous execution side of ctrl+shft. `ctrl` manages your environment; `shft` manages your work queue.

shft has two faces:

1. **CLI tool** — a bash command that runs locally, picks issues from your backlog, and drives Claude Code to implement them.
2. **Sandcastle** — a GitHub Actions framework that turns labels into agent workflows, running the same engine in CI.

Both use the same TypeScript engine under the hood.

## Two Execution Modes

| Mode | Command | How it works |
|------|---------|-------------|
| **HITL** | `shft run` | Claude with `--permission-mode acceptEdits` — you watch and approve each edit |
| **AFK** | `shft afk [n]` | Autonomous loop — picks issues, implements, commits, closes, repeats for `n` iterations (default 5) |

## Commands

| Command | Purpose |
|---------|---------|
| `shft run` | Start a HITL session |
| `shft afk [n]` | Start an AFK loop (`n` iterations, default 5) |
| `shft status` | Show loop state, open issues, plan progress |
| `shft stop` | Signal the AFK loop to stop after current iteration |
| `shft log [-f]` | Show recent log entries (`-f` to follow) |
| `shft issues` | List open GitHub issues sorted by priority |
| `shft next` | Show the next issue to work on |
| `shft done` | Mark current issue as complete |
| `shft plan` | View/edit the working plan |
| `shft engine on\|off\|status` | Switch between bash and TypeScript engines |
| `shft proxy start\|stop\|status` | Manage the LiteLLM/Copilot proxy daemon |
| `shft validate` | Run AFK environment validation |
| `shft mint` | Test GitHub App token minting |
| `shft context` | Show current context detection results |
| `shft help` | Show all commands |

## Task Selection Priority

The agent picks issues in this order (defined in `prompt.md`):

1. Critical bugfixes — bugs block other work
2. Development infrastructure — tests, types, dev scripts
3. Tracer bullets — small end-to-end slices validating approach
4. Polish and quick wins
5. Refactors

---

## Sandcastle Platform

Sandcastle is a label-driven autonomous agent platform built on GitHub Actions. Apply a label to a GitHub issue or PR, and a workflow fires to plan, implement, review, or merge — no human intervention required for routine tasks.

For full specifications, see [`docs/platform-spec.md`](docs/platform-spec.md).

### How It Works

```
Issue created
  │
  ▼
Label applied (e.g. agent:implement)
  │
  ▼
GitHub Actions workflow fires
  │
  ▼
Engine runs: checkout → prompt → agent → structured output → side effects
  │
  ▼
Result: PR opened / review posted / issues created / branch merged
```

### Label State Machine

Labels are the control plane. Each label maps to a workflow:

**Issue triggers:**
- `agent:plan` — Decompose a PRD into sub-issues
- `agent:review` — Review an issue for clarity and feasibility
- `agent:implement` — Implement a single issue (branch → code → PR)
- `agent:implement-prd` — Implement all slices of a PRD
- `agent:architecture-review` — Scoped architecture review

**PR triggers:**
- `agent:auto-fix` — Auto-fix review feedback (scored by comment quality)
- `agent:merge` — Squash-merge when checks pass
- `agent:update-branch` — Rebase against base branch

**State labels:**
- `queued` — Ready for the next scheduled batch
- `in-progress` — Agent is working on it
- `blocked` — Needs human intervention
- `review-cap-reached` — Hit the review round limit

**Classification:**
- `afk` — Safe for autonomous execution
- `hitl` — Requires human judgment

See [`docs/triage-labels.md`](docs/triage-labels.md) for the full label reference.

### Data Flow

```
                    ┌─────────────────┐
                    │  GitHub Issue    │
                    │  + label         │
                    └────────┬────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │  GitHub Actions  │
                    │  workflow        │
                    └────────┬────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │  .sandcastle/   │
                    │  run.ts         │◄── Vendored dispatcher
                    └────────┬────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │  Engine         │
                    │  main.ts        │◄── CLI arg parser + dispatch
                    └────────┬────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │  Workflow       │
                    │  (e.g.          │
                    │  implement-     │◄── Reads prompt, runs agent,
                    │  issue.ts)      │    validates output, acts
                    └────────┬────────┘
                             │
                    ┌────────┼────────┐
                    ▼        ▼        ▼
               Commits    PR/Review  Issues
               pushed     posted     created
```

### Installing Sandcastle

```bash
# Scaffold into a target repository
ctrl init-sandcastle [TARGET_DIR] [--sandbox none|docker]

# Check for drift against latest templates
ctrl update-sandcastle --dry-run

# Apply updates
ctrl update-sandcastle
```

`init-sandcastle` creates:
- `.sandcastle/` — Engine, prompts, extractions, hooks, scripts
- `.github/workflows/agent-*.yml` — Workflow files
- `.github/copilot-setup-steps.yml` — Copilot setup
- `sandcastle.config.json` — Configuration
- GitHub labels from `labels.json`

### Configuration

`sandcastle.config.json`:

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

All values have defaults. Override any with environment variables (prefix `SANDCASTLE_`, e.g. `SANDCASTLE_MODEL`).

---

## TypeScript Engine

The TypeScript engine (`shft/engine/`) replaces shft's raw bash-to-Claude pipeline with schema-validated typed results via `@ai-hero/sandcastle`. Enable it with `shft engine on` or `SHFT_ENGINE=ts`.

### Architecture

```
shft/engine/
  main.ts          ← Thin CLI dispatcher (parses args, delegates to workflows)
  schemas/         ← Zod schemas for each workflow's output
  workflows/       ← TypeScript workflow implementations (including parallel orchestration)
  prompts/         ← Prompt templates consumed by sandcastle
  lib/             ← Shared utilities (semaphore, diff parsing, PR comments)
```

**Key principle:** separation of thinking from acting. The agent emits structured JSON data; TypeScript code acts on it (posting reviews, creating issues, merging branches).

### Workflows

| Workflow | Registry name | Purpose |
|----------|--------------|---------|
| Parallel | `parallel` | Plan phase selects issues, then fan-out concurrent implementation + merge |
| Implement Issue | `implement-issue` | Single-issue implementation with `<promise>COMPLETE</promise>` signal |
| Implement PRD | `implement-prd` | Implements all slices of a PRD issue |
| Implement PR | `implement-pr` | Address PR review feedback, post replies and inline comments |
| Address Review | `address-review` | Score review comments and auto-fix or defer |
| Review | `review` | Code review — posts a GitHub review with summary and inline comments |
| Review Issue | `review-issue` | Reviews an issue for clarity and feasibility |
| Write PR | `write-pr` | Creates a PR from a completed branch |
| Update Branch | `update-branch` | Rebases or merges base branch into PR branch |
| Architecture Review | `architecture-review` | Scoped architecture analysis |
| To-Issues PRD | `to-issues-prd` | Decompose a PRD issue into sub-issues |

### CLI Flags

| Flag | Default | Purpose |
|------|---------|---------|
| `--repo` | required | Absolute path to the target repo |
| `--workflow` | `implement` | Which workflow to run |
| `--max-iterations` | `1` | Max agent iterations per issue |
| `--max-issues` | `5` | Max issues for plan phase |
| `--max-parallel` | `4` | Max concurrent agents (parallel workflow) |
| `--issue` | — | Target a specific issue number |
| `--branch` | — | Branch name override |
| `--pr` | — | PR number (for review/implement-pr) |
| `--dry-run` | `false` | Print without acting (to-issues-prd) |

### How the Engines Compare

**Bash engine (default):**
```
shft afk N → afk.sh → _build_prompt.sh → claude CLI → parse stream → loop
```

**TypeScript engine (`SHFT_ENGINE=ts`):**
```
shft afk N → afk.sh → npx tsx engine/main.ts --workflow parallel
  → dispatch("parallel") → workflows/parallel.ts
    → runPlan() → plan.md → PlanOutput (issue list)
    → Semaphore(maxParallel) for each issue
      → createSandbox(branch) → implement.md → commits
    → runMerge(completedBranches) → merge.md → MergeOutput
```

### Schemas

Each workflow produces Zod-validated structured output:

| Schema | Fields |
|--------|--------|
| `PlanOutput` (inline in `parallel.ts`) | `issues[].{number, title, branch}` |
| `MergeOutput` (inline in `parallel.ts`) | `merged[], failed[].{branch, reason}, testsPassed` |
| `ImplementPrOutput` | `threadReplies[], newInlineComments[], topLevelComments[]` |
| `ReviewOutput` | `summary, inlineComments[], replies[]` |
| `PrdSlicesOutput` | `slices[].{title, type, whatToBuild, acceptanceCriteria[], blockedBy[]}` |

Schema field aliasing via Zod `.transform()` handles LLM output variations (e.g. `file`/`path`, `body`/`comment`).

### Validation

- Inline comments are validated against `git diff` output — comments on lines not in the diff are silently dropped with a warning
- Thread reply `commentId`s are validated against fetched PR threads — invalid IDs are dropped with a warning
- `StructuredOutputError` fires when agent output doesn't match the expected schema

---

## Files

| File | Purpose |
|------|---------|
| `shft` | Main CLI — command routing, state management, environment validation |
| `afk.sh` | AFK loop — engine dispatch, iteration control, locking |
| `once.sh` | Single HITL run — invokes Claude with issue context |
| `prompt.md` | System prompt injected into AFK/HITL sessions |
| `_build_prompt.sh` | Assembles the full prompt from issues + recent commits |
| `_proxy_env.sh` | Proxy environment setup (reads `~/.shft/proxy.json`) |
| `engine/` | TypeScript engine (see above) |
| `templates/` | Sandcastle installable templates (prompts, workflows, labels) |
| `docs/` | Platform specification and label reference |

## Security

- AFK mode uses **short-lived GitHub App tokens** minted per iteration via `bin/mint_github_app_token.py`
- **Repo-scoped lock directory** (`${TMPDIR:-/tmp}/shft-afk-<repo-hash>.lock`) prevents concurrent AFK loops per repository; legacy `/tmp/shft-afk.lock` is detected and surfaced as a warning
- AFK invokes Claude with `--dangerously-skip-permissions`; on Linux/macOS it typically runs inside the Docker-backed `srt` sandbox, but on WSL/MSYS it runs unsandboxed with an explicit warning (deny rules still apply)
- The TypeScript engine currently uses `noSandbox()` on all platforms; Docker-backed sandboxing is not yet wired in
