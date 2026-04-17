---
name: atomic-commits
description: "Use this skill whenever work has been completed and needs to be committed. Enforces atomic commits — one logical change per commit with a conventional commit message — so changes are broken into discrete, independently revertable steps. Trigger any time the user asks to 'commit', 'save progress', 'checkpoint my work', or has just finished implementing a feature, fix, or refactor."
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

### 1. Survey the diff

Start by reviewing everything that changed:

```bash
git diff          # unstaged changes
git diff --staged # already staged changes
git status        # full picture of modified/untracked files
```

Identify natural "seams" — boundaries between distinct logical changes. These become your commit boundaries.

### 2. Group into logical units

Decompose the diff into an ordered commit plan. Each unit should have a single clear purpose:

```
1. feat(auth): add JWT refresh token rotation
2. test(auth): cover token rotation edge cases
3. chore(config): add REFRESH_SECRET env variable
```

If a change touches unrelated concerns, split the file-level staging accordingly using `git add -p` for partial file staging.

### 3. Stage and commit each unit

Work through each logical unit one at a time:

```bash
git add <specific-files>        # stage only what belongs to this commit
git add -p <file>               # stage partial file changes if needed
git diff --staged               # confirm exactly what's going in
git commit -m "<type>(<scope>): <summary>"
```

Never use `git add .` blindly — always confirm what's staged before committing.

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

If your message needs "and" to describe what changed — split it into two commits.
