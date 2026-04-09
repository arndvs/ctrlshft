---
name: do-work
description: "Core execution loop for implementing tasks. Use when asked to 'do work', 'implement', 'build this', 'fix this', 'plan execute clear', 'plan then execute', 'work loop', or when working through a plan or backlog item."
---

# Do Work

Output "Read Do Work skill." to chat to acknowledge you read this file.

## Workflow

### 1. Understand

Read any referenced plan, PRD, or GitHub issue. If none provided, clarify the task with the user before proceeding.

### 2. Plan (optional)

If the task has not already been planned, create a plan for it. Break large tasks into vertical slices (tracer bullets) — each slice should touch all layers end-to-end rather than building layer by layer.

Skip this step if a plan or PRD already exists.

### 3. Implement

Write the code. Follow the conventions already established in the codebase — read a sample existing file of the same type before creating new ones.

### 4. Validate

Run the project's feedback loops until they pass cleanly. Auto-detect from the workspace:

- **package.json** → look for `test`, `typecheck`, `type-check`, `lint` scripts. Run with the project's package manager (npm/pnpm/yarn/bun).
- **composer.json** → look for `test`, `lint`, `phpstan` scripts. Run with `composer run`.
- **Makefile** → look for `test`, `lint`, `check` targets. Run with `make`.
- **pyproject.toml / setup.cfg** → look for pytest, mypy, ruff. Run directly.
- **Pre-commit hooks** → if `.husky/` or `.pre-commit-config.yaml` exists, the commit step will trigger them automatically.

If no feedback loops are detected, tell the user and ask what validation commands to run.

### 5. Commit

Once validation passes, commit the work using atomic commit format (one logical change per commit, conventional commit message).

### 6. Context Check

If this is one phase of a multi-phase plan, clear context before starting the next phase. Pass `@prd` and `@plan` to the fresh context.

If context usage is over 40%, clear and start fresh — you're leaving the smart zone where output quality is highest.
