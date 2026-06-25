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
