---
description: "Tooling & CLI conventions — shell scripts, CLI entry points, hooks, and package scripts: verify with real-command tests, prefer existing tooling, justify new dependencies."
paths:
  - "bin/**"
  - "hooks/**"
  - "shft/**/*.sh"
  - "test/**/*.sh"
  - "**/*.sh"
  - "**/*.bash"
  - "package.json"
---

# Tooling & CLI Conventions

- **Verify CLI behavior with automated tests** that invoke the real command and assert on exit code and output. A command that "worked when I ran it" is not durable coverage.
- **Manual smoke tests are supplemental, not the only check.** Encode the durable expectations as a test (e.g. under `test/`) so they survive future changes.
- **Prefer existing tooling.** Reach for the scripts, helpers, and commands that already exist before writing new ones.
- **Add a bespoke script only after the same manual work has repeated.** When you do, document what it does, how to run it, and why it exists.
- **New third-party dependencies require explicit human sign-off** — do not add a package, binary, or external tool to a workflow without it.

## Dotfiles Test Conventions

### Testing tiers

| Tier | Trigger | Env | Suites run |
|------|---------|-----|------------|
| Pre-commit | `git commit` (automatic) | `SKIP_SLOW_TESTS=1` | All except `hooks` and `proxy-scripts` (~6.5s) |
| Full suite | `npm test` / CI | — | All 7 suites in parallel (~31s) |
| Single suite | `bash test/<suite>.sh` | — | One suite only |

**Do NOT run `npm test` separately before committing when the hook is installed and `jq` is available.** The pre-commit hook already runs the fast suite in that environment. If hooks are disabled or `jq` is missing, run `npm test` manually.

### Parallel group contract

The `hooks-integration.sh` and `lifecycle.sh` suites run test groups in parallel. When adding tests:

1. Place tests inside a `_group_<name>()` function
2. Register the full function name (for example, `_group_init`) in the `_GROUPS` array
3. Each group runs in a background subshell — **no shared mutable state across groups** (use per-group temp directories)
4. Groups write `pass`/`fail` + failure details to temp files; the harness aggregates results after `wait`

### Process spawn awareness (Windows)

Each `_test` invocation spawns bash + git processes. On Windows (MINGW64) this is ~10x slower than Linux. Minimize process spawns by batching related assertions within a single `_test` call where practical.
