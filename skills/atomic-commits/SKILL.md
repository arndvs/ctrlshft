---
name: atomic-commits
description: "Use this skill whenever working on a coding task that involves multiple changes, file edits, or feature implementation. Enforces atomic commits — one logical change per commit with a conventional commit message — so work is broken into discrete, independently revertable steps. Trigger this skill any time the user asks to 'commit', 'save progress', 'checkpoint my work', or is doing iterative development, refactoring, bug fixes, or feature additions across multiple files."
disable-model-invocation: true
---

# Atomic Commits

Output "Read Atomic Commits skill." to chat to acknowledge you read this file.

## Core Principles

- **One logical change per commit** — each commit does exactly one thing
- **Self-contained** — every commit leaves the codebase in a working state
- **Independently revertable** — any commit can be reverted without breaking other commits
- **Descriptive** — the commit message fully explains _what_ changed and _why_

---

## Workflow

### 1. Understand

Before touching any files, clarify the full scope of work:

- What is the end goal?
- What files will change?
- Are there dependencies between changes?

Identify natural "seams" — boundaries between distinct logical changes. These become your commit boundaries.

### 2. Plan

Decompose the work into an ordered list of atomic steps. Each step should:

- Have a single clear purpose (fix a bug, add a function, update a config, add a test)
- Not depend on uncommitted changes from a later step
- Be completable and verifiable on its own

Write out the plan explicitly before starting. Example:

```

1. feat: add input validation to login form
2. test: add unit tests for login validation
3. refactor: extract validation logic to shared util
4. chore: update README with validation rules

```

### 3. Implement

Work through each step one at a time:

- Make only the changes for the current step
- Do not mix unrelated changes (e.g., don't fix a typo while adding a feature — that's a separate commit)
- If you notice something unrelated that needs fixing, note it but do not fix it yet

### 4. Validate

Before staging each commit:

- Confirm the change is isolated — `git diff` should show only what belongs to this commit
- Confirm the codebase still works (run tests, linter, or build as appropriate)
- Confirm no unintended files are staged

```bash
git diff          # review unstaged changes
git diff --staged # review staged changes
git status        # confirm no surprise files
```

### 5. Commit

Stage only the relevant files for this logical change, then commit with a conventional commit message.

```bash
git add <specific-files>   # never use `git add .` blindly
git commit -m "<type>(<scope>): <short summary>"
```

---

## Conventional Commit Message Format

```
<type>(<scope>): <short imperative summary>

[optional body: explain WHY, not what — the diff shows what]

[optional footer: breaking changes, issue refs]
```

### Types

| Type       | When to use                                |
| ---------- | ------------------------------------------ |
| `feat`     | New feature or capability                  |
| `fix`      | Bug fix                                    |
| `refactor` | Code restructuring with no behavior change |
| `test`     | Adding or updating tests                   |
| `docs`     | Documentation only                         |
| `chore`    | Tooling, deps, config, build scripts       |
| `style`    | Formatting, whitespace (no logic change)   |
| `perf`     | Performance improvement                    |
| `revert`   | Reverting a prior commit                   |

### Rules

- Summary line: 50 chars or fewer, imperative mood ("add", not "added" or "adds")
- No period at end of summary
- Body: wrap at 72 chars, explain motivation and context
- Reference issues in footer: `Closes #42`, `Fixes #17`

### Examples

```
feat(auth): add JWT refresh token rotation

Tokens now rotate on each use to limit exposure window.
Previous single-token approach left sessions vulnerable
to replay attacks if a token was intercepted.

Closes #88
```

```
fix(api): return 404 instead of 500 for missing user
```

```
refactor(utils): extract date formatting into shared helper

Three components were duplicating the same locale-aware
date formatting logic. Centralizing reduces drift risk.
```

---

## What Makes a Good Atomic Commit?

✅ **Good** — single, clear purpose:

- `fix: correct off-by-one in pagination offset`
- `feat(search): add debounce to search input`
- `test: cover edge cases for empty cart checkout`

❌ **Bad** — too broad or mixed:

- `fix stuff`
- `WIP`
- `feat: add search, fix bug, update styles, refactor utils`

If your diff touches unrelated files or your message needs "and" to describe what changed — split it.

---

## Handling Work-in-Progress

If you need to context-switch before a logical unit is complete:

```bash
git stash push -m "wip: <description>"   # stash cleanly
# or
git commit -m "wip: <description>"        # commit as WIP, squash later
```

To squash WIP commits before pushing:

```bash
git rebase -i HEAD~<n>   # interactive rebase to squash/fixup WIP commits
```

---

## Common Patterns

### Bug fix + test (two commits)

```bash
git add src/utils/validate.js
git commit -m "fix(validate): reject empty string as valid email"

git add tests/validate.test.js
git commit -m "test(validate): add case for empty string email input"
```

### Refactor before feature (two commits)

```bash
# First: make the code easy to change
git add src/auth/
git commit -m "refactor(auth): extract token parsing to standalone function"

# Then: add the feature
git add src/auth/ src/middleware/
git commit -m "feat(auth): support Bearer token in Authorization header"
```

### Config + code change (two commits)

```bash
git add .env.example config/defaults.js
git commit -m "chore(config): add RATE_LIMIT_MAX env variable"

git add src/middleware/rateLimit.js
git commit -m "feat(rateLimit): apply configurable request rate limiting"
```

```

```
