# shft

The autonomous execution side of ctrl+shft. `ctrl` manages your environment; `shft` manages your work queue.

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
| `shft afk --worktree [n]` | Start AFK in an isolated git worktree/branch so the IDE checkout stays untouched |
| `shft status` | Show loop state, open issues, plan progress |
| `shft stop` | Signal the AFK loop to stop after current iteration |
| `shft worktrees` | List or remove AFK-created git worktrees |
| `shft log [-f]` | Show recent log entries (`-f` to follow) |
| `shft issues` | List open GitHub issues sorted by priority |
| `shft next` | Show the next issue to work on |
| `shft done` | Mark current issue as complete |
| `shft plan` | View/edit the working plan |
| `shft engine on\|off\|status` | Switch between bash and TypeScript engines |
| `shft proxy on\|off\|start\|stop\|status` | Toggle routing and manage the LiteLLM/Copilot proxy daemon |
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

## Sandcastle Platform

Sandcastle is the CI-triggered AFK agent platform extracted under `shft/`. It stamps workflow YAMLs and a vendored TypeScript engine into any repository, then drives issue planning, implementation, PR review, feedback fixes, branch updates, and merge handoffs through GitHub labels.

### Install in a repo

Run this from the target repository root:

```bash
ctrl init-sandcastle --branch main --model claude-opus-4-6 --sandbox none
```

`ctrl init-sandcastle` is a stamp-and-own installer. It copies files into the target repo instead of symlinking them, which keeps GitHub Actions independent of `~/dotfiles`:

```
<repo>/
├── .github/
│   ├── workflows/agent-*.yml
│   └── copilot-setup-steps.yml
├── .sandcastle/
│   ├── engine/                    ← vendored TypeScript runners
│   ├── prompts/                   ← project-specific prompt overrides
│   ├── templates/                 ← default prompts + extraction prompts
│   ├── scripts/                   ← setup and validation helpers
│   ├── hooks/                     ← optional Claude Code hooks
│   ├── run.ts                     ← workflow dispatcher
│   └── CODING_STANDARDS.md
└── sandcastle.config.json
```

If `.sandcastle/` already exists, init refuses to overwrite it unless `--force` is passed. Existing `sandcastle.config.json`, `.sandcastle/prompts/`, and `.sandcastle/CODING_STANDARDS.md` are preserved.

### Keep vendored files current

Run this from an initialized repo:

```bash
ctrl update-sandcastle --dry-run
```

`ctrl update-sandcastle` compares the repo-owned files against `~/dotfiles/shft/` and shows drift for:

- `.sandcastle/engine/lib/`, `schemas/`, and `workflows/`
- `.sandcastle/engine/package.json` and `tsconfig.json`
- `.sandcastle/templates/prompts/` and `extractions/`
- `.sandcastle/scripts/` and `hooks/`
- `.github/workflows/agent-*.yml`
- `.github/copilot-setup-steps.yml`

Project-specific prompts, config, and coding standards are never overwritten by drift updates.

The vendored engine intentionally excludes source test files. Its `package.json` is rendered with a no-op `test` script and a working `typecheck` script, so consumer repos can run package checks without a false Vitest failure from an empty test suite. The engine package also lists reviewed pnpm build approvals for native dependencies used by `tsx`/Vitest, avoiding a blanket lifecycle-script allow-all while still letting runtime binaries initialize correctly.

### Source layout in dotfiles

```
shft/
├── engine/
│   ├── lib/              ← config, dispatch, retries, diff parsing, GitHub helpers
│   ├── schemas/          ← Zod output schemas
│   ├── workflows/        ← TypeScript workflow runners
│   ├── package.json
│   └── tsconfig.json
└── templates/
    ├── workflows/        ← GitHub Actions templates
    ├── prompts/          ← default agent prompts
    ├── extractions/      ← structured-output extraction prompts
    ├── hooks/            ← optional git hooks
    ├── scripts/          ← helper scripts copied into adopters
    ├── sandbox/          ← optional Docker sandbox template
    ├── copilot-setup-steps.yml
    ├── labels.json
    └── run.ts
```

### Configuration

Each initialized repo gets `sandcastle.config.json`. Missing fields fall back to engine defaults, and selected values can be overridden by environment variables.

| Field | Default | Environment override | Purpose |
|-------|---------|----------------------|---------|
| `model` | `claude-opus-4-6` | `SANDCASTLE_MODEL`, `ANTHROPIC_MODEL` | Model used by runners |
| `baseBranch` | `main` | `SANDCASTLE_BASE_BRANCH` | Default branch used by workflow templates |
| `sandbox` | `none` | `SANDCASTLE_SANDBOX` | Only `none` is currently supported by the TypeScript engine |
| `promptDir` | `.sandcastle/prompts` | — | Project prompt override directory |
| `codingStandards` | `.sandcastle/CODING_STANDARDS.md` | — | Project standards document |
| `contextDoc` | `CONTEXT.md` | — | Project context document |
| `adrDir` | `docs/adr` | — | ADR directory |
| `packageManager` | `pnpm` | `SANDCASTLE_PACKAGE_MANAGER` | `npm`, `pnpm`, `yarn`, or `bun` |

Prompt resolution checks `.sandcastle/prompts/` first, then falls back to the templates directory passed by `.sandcastle/run.ts`.

### Workflow dispatcher

All GitHub Actions install engine dependencies with the configured package manager, then call the vendored dispatcher with the engine-local `tsx` binary:

```bash
./.sandcastle/engine/node_modules/.bin/tsx .sandcastle/run.ts <workflow-name> [args]
```

Registered workflow names are defined in `shft/engine/lib/dispatch.ts`:

| Workflow | Required args | Purpose |
|----------|---------------|---------|
| `review-issue` | `--issue N` | Review a newly labeled issue and decide whether it needs PRD planning or direct implementation |
| `plan-issue` | `--issue N` | Break a PRD issue into implementation sub-issues |
| `implement-issue` | `--issue N` | Implement a single issue and produce PR review metadata |
| `implement-prd` | `--prd-number N --prd-title TEXT --sub-issue-number N --sub-issue-title TEXT --branch REF` | Implement the next open sub-issue for a PRD branch |
| `write-pr` | `--issue N --issue-title TEXT --branch REF` | Draft a PR title and description for a single issue |
| `write-prd-pr` | `--prd-number N --prd-title TEXT` | Draft a PR title and description for a PRD branch |
| `fix-pr-feedback` | `--pr N` | Address review comments on an open PR |
| `update-branch` | `--pr N --branch REF --base-ref REF` | Update a PR branch against the base branch |
| `merge-pr` | `--pr N` | Squash-merge and delete the branch |
| `architecture-review` | — | Run the scheduled architecture review pass and write PRD output files |
| `check-stale-prs` | — | List stale open PRs for scheduled maintenance |

### GitHub Actions templates

`shft/templates/workflows/` contains the workflow templates installed into `.github/workflows/`:

| Template | Trigger | Label / event |
|----------|---------|---------------|
| `agent-review-issue.yml` | `issues:labeled` | Entry label `Sandcastle` |
| `agent-plan-issue.yml` | `issues:labeled` | `agent:review` |
| `agent-implement-issue.yml` | `issues:labeled` | `agent:implement` |
| `agent-implement-prd.yml` | `issues:labeled` | `agent:implement-prd` on the parent PRD |
| `agent-fix-pr-feedback.yml` | `pull_request_target:labeled` | `agent:fix` |
| `agent-update-branch.yml` | `pull_request_target:labeled` | `agent:update-branch` |
| `agent-merge-pr.yml` | `pull_request_target:labeled` | `agent:merge` |
| `agent-architecture-review.yml` | `schedule`, `workflow_dispatch` | Creates `source:architecture-review` PRD issues |
| `agent-promote-queued.yml` | `issues:closed` | Promotes unblocked `agent:queued` issues |
| `agent-check-stale-prs.yml` | `schedule`, `workflow_dispatch` | Scheduled maintenance |
| `sandcastle-ci.yml` | `push`/`pull_request` on `.sandcastle/engine/**` | Validates the vendored engine (frozen install + typecheck); always vendored |
| `proxy-canary.yml` (in `workflows-proxy/`) | `schedule`, `workflow_dispatch` | Proxy health probe; opt-in only with `--with-proxy-canary` (default off) |

Workflow templates use `{{DEFAULT_BRANCH}}`; init and update resolve it from `--branch` or `sandcastle.config.json`. Proxy routing is enabled by default (`--with-proxy`); pass `--no-proxy` to disable it. The `proxy-canary.yml` scheduled monitor is a separate opt-in: pass `--with-proxy-canary` to install it, or `--no-proxy-canary` (the default) to skip it. The `proxyCanary` field in `sandcastle.config.json` records this choice independently from `proxy`.

> **Central canary model:** Most consumer repos should **not** install their own proxy canary. Run one canonical scheduled canary in the proxy owner repo (the repo that operates the LiteLLM/Copilot proxy host). Consumer repos rely on cheap preflight health gates at workflow start — if the proxy is down, the preflight fails fast and the workflow exits before spending model tokens. Only opt into `--with-proxy-canary` in a consumer repo when you intentionally need repo-local scheduled monitoring (e.g., an independent availability SLA).

The canonical dogfood smoke-test contract for these templates is documented in `shft/docs/full-smoke-matrix.md`.

### Labels and secrets

Init creates the labels from `shft/templates/labels.json` when the GitHub CLI is authenticated and can resolve the current GitHub repository. In local-only repos with no remote, init skips label creation and prints the manual command to run after adding a remote. The label state machine uses:

- Entry/control labels: `Sandcastle`, `agent:review`, `agent:implement`, `agent:implement-prd`, `agent:fix`, `agent:update-branch`, `agent:merge`
- Status labels: `agent:in-progress`, `agent:pr-open`, `agent:queued`, `agent:blocked`
- Provenance labels: `source:architecture-review`

Required GitHub Actions secrets:

- `LITELLM_BASE_URL` — points Claude-compatible model traffic at the LiteLLM proxy backed by GitHub Copilot
- `LITELLM_MASTER_KEY` — authenticates workflow calls to the LiteLLM proxy
- `AGENT_PAT` — optional but recommended; label mutations made with `GITHUB_TOKEN` do not trigger downstream workflows, so `AGENT_PAT` is needed for chains such as `agent:implement` → `agent:review` and PRD sub-issue chaining

For hosted GitHub Actions, see [the EC2 hosted proxy runbook](docs/hosted-proxy-ec2-runbook.md). Sandcastle expects an HTTPS reverse proxy endpoint (for example Caddy or nginx) while the LiteLLM app port remains bound to localhost on the proxy host.

### Structured output and validation

Workflow runners use `@ai-hero/sandcastle` plus Zod schemas for typed output. Two shared retry helpers keep side-effecting work from being repeated:

- `runWithRetry()` retries schema extraction by resuming the failed session with validation feedback.
- `runWithExtraction()` runs side-effecting work first, then resumes the produced session only to extract structured output. Produce prompts should not contain structured-output instructions; extraction prompts own the output contract.

Validation rules include:

- Inline comments are validated against the current PR diff before posting.
- Review thread replies are matched against fetched GitHub review threads before posting.
- `StructuredOutputError` failures are surfaced so workflows can mark the issue or PR `agent:blocked` instead of failing silently.

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

## Security

- AFK mode uses **short-lived GitHub App tokens** minted per iteration via `bin/mint_github_app_token.py`
- **Repo-scoped lock directory** (`${TMPDIR:-/tmp}/shft-afk-<repo-hash>.lock`) prevents concurrent AFK loops per repository; legacy `/tmp/shft-afk.lock` is detected and surfaced as a warning
- By default, local `shft afk` edits the current checkout and refuses to start on a dirty working tree unless `--force` is passed. Use `shft afk --worktree` when you want to keep working in the IDE while AFK runs.
- `shft afk --worktree` creates one isolated git worktree and branch for the AFK run. Multiple issues in the same run share that branch, so dependent follow-up work can build on earlier AFK commits. `shft status` shows the active worktree and branch, and `shft worktrees` lists/removes AFK-created worktrees after review.
- AFK invokes Claude with `--dangerously-skip-permissions`; on Linux/macOS it typically runs inside the Docker-backed `srt` sandbox, but on WSL/MSYS it runs unsandboxed with an explicit warning (deny rules still apply)
- The TypeScript engine currently uses `noSandbox()` on all platforms; Docker-backed sandboxing is not yet wired in
