# Hooks

Claude Code lifecycle hooks — shell scripts that fire on tool use and session events.

## How Hooks Work

Claude Code hooks are **JSON configuration** in `~/.claude/settings.json`, not standalone files. Each hook references a shell script that receives JSON on stdin and communicates via exit codes:

- **Exit 0** — allow (tool proceeds / agent stops normally)
- **Exit 2** — block (tool use rejected / agent continues working)

Bootstrap symlinks `hooks/` → `~/.claude/hooks/`. The hook configuration lives in `dotfiles/.claude/settings.json` (the source of truth), which `ctrl bootstrap` deploys directly to `~/.claude/settings.json`.

## Git Hook Dispatchers

Global Git hooks live in `git-hooks/` and are installed by bootstrap with `git config --global core.hooksPath ~/dotfiles/git-hooks`.

- `git-hooks/pre-commit` is the canonical feedback-loop dispatcher. It delegates to project hooks first, then runs typecheck/tests from `package.json` when no project hook exists.
- `git-hooks/generic-hook` is the canonical no-fallback dispatcher for hooks that only delegate to project-local hooks.
- `git-hooks/commit-msg`, `git-hooks/post-commit`, and `git-hooks/prepare-commit-msg` must keep the executable body of `generic-hook` byte-identical after the header comments.
- `git-hooks/pre-push` has a public-promotion guard before the generic delegation tail; its public ctrl+shft URL matching uses the shared `normalize_ctrlshft_remote_url` helper in `bin/_lib.sh`, the same helper used by `bin/validate-remotes.sh`.

Run `bash bin/validate-git-hooks.sh` after editing `git-hooks/`. Bootstrap and `validate-env.sh` run the same check so copied dispatchers cannot silently drift.

## Matcher Enforcement Gap (Copilot Chat) — verified 2026-07-27

**GitHub Copilot Chat does not enforce the `matcher` field at all.** Ground truth: the raw `main.jsonl` debug log (not the OTel-exported summaries) records each hook invocation's actual stdin JSON. Decoding it shows:

- Copilot Chat sends its own **native tool names** to hooks — `read_file`, `grep_search`, `file_search`, `run_in_terminal`, `runSubagent`, `create_file`, `replace_string_in_file`, `list_dir`, `manage_todo_list`, `get_errors`, `memory` — never Claude Code's canonical names (`Read`, `Grep`, `Glob`, `Bash`, `Task`, `Write`).
- Every hook registered under a given event (e.g. all six `PreToolUse`/matcher:`"Bash"` hooks) fires for **every tool call regardless of matcher** — `secret-guard.sh`, `migration-guard.sh`, `git-workflow-gate.sh`, `plan-quality-gate.sh`, `plan-review-phase2.py`, and `test-gate.sh` all execute on `read_file`, `create_file`, `memory`, `manage_todo_list`, etc., not just on Bash-equivalent commands.

Every hook survives this **except when it explicitly checks `tool_name` for a literal Claude Code string**. Two real bugs found and fixed this way:

- `plan-quality-gate.sh` had `[[ "$TOOL_NAME" == "Bash" ]] || exit 0` — this can never match `run_in_terminal`, so the hook silently dead-ended on every Copilot Chat call. Fixed by removing the tool_name gate; the existing `tool_input.command` presence check below it is the correct, environment-agnostic filter (same pattern `secret-guard.sh`/`migration-guard.sh`/`test-gate.sh` already used).
- `exploration-scope-guard.sh` (new, see below) originally matched only `Read|Grep|Glob|Task` — fixed to also match `read_file|grep_search|file_search|runSubagent`.

**Practical consequence:** the `matcher` field in `.claude/settings.json` is effectively decorative under Copilot Chat — it documents intent and still works in Claude Code CLI, but every hook must independently re-check the relevant `tool_input` field (or, if it truly needs to distinguish tool types, check both naming schemes) rather than trust the matcher to have filtered anything. This also means every `PreToolUse`/matcher:`"Bash"` hook is spawning a subprocess on every single tool call in Copilot Chat sessions, not just Bash calls — a real, uncounted performance tax on top of the hook-fan-out issue documented above.

## Hooks

| Script | Event | Matcher | Behavior |
|--------|-------|---------|----------|
| `secret-guard.sh` | PreToolUse | Bash | Blocks commands that expose credentials (echo $TOKEN, bare env/printenv, cat secrets/) |
| `migration-guard.sh` | PreToolUse | Bash | Blocks database migration commands targeting non-test databases |
| `git-workflow-gate.sh` | PreToolUse | Bash | Enforces git safety: no commit to main, conventional messages, no force-push, no dirty-tree switch, no cd+git chains |
| `plan-quality-gate.sh` | PreToolUse | Bash | Warns when scaffolding (mkdir, npx create-, etc.) has no plan file; when a plan exists, validates required sections and emits a checklist summary |
| `plan-review-phase2.py` | PreToolUse | Bash | Phase 2 PR diff comparison — warns when `gh pr create` diff is missing planned files (CC-80/174/175) |
| `feedback-memory-gate.py` | PostToolUse | Write | Warns when feedback memory files describe bugs without an issue tracker reference |
| `test-gate.sh` | PreToolUse | Bash | Runs project tests before `git commit`; blocks commit if tests fail |
| `git-post-push.sh` | PostToolUse | Bash | Info nag when no PR exists after pushing to a feature branch |
| `stale-branches.sh` | SessionStart | — | Reports merged or stale (>14d) local branches at session start |
| `format-check.sh` | Stop | — | Detects Biome/Prettier/ESLint and formats modified files (non-blocking) |
| `typecheck.sh` | Stop | — | Runs `tsc --noEmit` on TypeScript projects; blocks stop until types pass |
| `compaction-guard.sh` | PreCompact | auto | Blocks auto-compaction at ~95% context; directs agent to follow handoff protocol |
| `hud-session.sh` | SessionStart, Stop | — | Emits session lifecycle events to `events.jsonl` for the HUD |
| `hud-reads.sh` | PostToolUse, InstructionsLoaded | Read | Emits read events to the HUD — tracks which instructions/skills/rules loaded and external file reads |
| `context-warning.sh` | UserPromptSubmit | — | ⚠️ STUB: graduated context warnings at 40/70% (pending statusLine experiment) |
| `exploration-scope-guard.sh` | PreToolUse | Read\|Grep\|Glob\|Task | Counts raw exploration calls per session; warns every 15 calls to delegate to a subagent (resets on `Task` spawn) |
| `session-scope-warning.sh` | UserPromptSubmit | — | Graduated turn-count warnings at 20 and every 20 turns past 40 — same intent as `context-warning.sh` but keyed on turn count, not context %, so it doesn't depend on the statusLine bridge |

## Requirements

- **jq** — all fail-closed hooks (secret-guard, migration-guard, git-workflow-gate) **require** jq and deny if missing. Fail-open hooks (stale-branches, plan-quality-gate, git-post-push) skip gracefully if jq is missing.
- **Python 3** — `plan-review-phase2.py` and `feedback-memory-gate.py` require Python 3.
- **npx** — format-check and typecheck use npx to run project-local tools.

## Editor Compatibility

Hooks are a **Claude Code CLI** feature. They fire in:
- Claude Code CLI (`claude`)
- VS Code with Claude Code extension

**Update (verified 2026-07-27):** GitHub Copilot Chat in VS Code Insiders now also resolves and fires these hooks — confirmed via `Hook Discovery` telemetry spans tagged `copilot_chat.event_details` in agent debug logs. Do not assume Copilot Chat sessions are hook-free; the fan-out issue below applies there too. The scripts themselves are portable bash — they can be run manually or referenced from other tools.

## External Hook Sources & Fan-Out (verified 2026-07-27)

VS Code resolves hooks additively from **up to 5 locations** per session, not just `.claude/settings.json`:

1. `~/.copilot/hooks/orca.json` — injected by the **Orca** desktop app, entirely outside dotfiles. Historically registered all 13 hook event types with **no matchers**, so every entry fired on every single tool call regardless of tool type. This was the dominant source of hook overhead across every project (confirmed via debug-log analysis: ~11-25 hook spans per tool call). Fix: in Orca settings → Agents, toggle off **"Agent status hooks"** — this makes Orca rewrite `orca.json` down to an empty hook set immediately (verified; no restart needed). A `.bak` of the old file is left in place.
2. `~/.claude/settings.json` — the dotfiles-managed global config (this repo's source of truth, deployed by `ctrl bootstrap`).
3. `<project>/.github/hooks/` — project-level override folder (rarely populated).
4. `<project>/.claude/settings.local.json` — project-level local override (rarely populated).
5. `<project>/.claude/settings.json` — project-level config.

**"Dogfood tax":** because this repo (`ctrlshft-public`) *is* the dotfiles source that gets deployed to `~/.claude/settings.json`, its own tracked `.claude/settings.json` is byte-identical to the globally-deployed one. When your working directory is inside this repo, VS Code loads both additively and every hook defined in `.claude/settings.json` fires twice. This does **not** happen in downstream client repos, which don't carry a full copy of the hook config. There is no code fix for this — it's inherent to dogfeeding the config in the repo that produces it — but it's worth knowing when auditing hook counts from a session run inside this repo specifically.

## Context Awareness

**Compaction guard** (`compaction-guard.sh`) — fully operational **in Claude Code CLI**. Blocks auto-compaction at ~95% context and directs the agent to commit work and follow the handoff protocol instead. Manual `/compact` is unaffected. This mechanically enforces the `global.instructions.md` policy: "prefer clearing context over compacting." See the Copilot Chat caveat below.

**Graduated warnings** (`context-warning.sh`) — stub, pending experiment. Hook input JSON does not include context usage. However, the `statusLine` setting receives `context_window.used_percentage` (confirmed in env vars docs). A statusLine command can write the percentage to a state file; this hook reads it and injects warnings via `additionalContext` at 40% and 70%. Run `hooks/experiments/statusline-probe.sh` to discover the statusLine input format, then fill in the bridge. See `hooks/experiments/README.md` for setup instructions.

`statusLine` is a Claude Code CLI concept — there's no confirmed GitHub Copilot Chat equivalent, so even a finished bridge would only warn in Claude Code CLI sessions. `session-scope-warning.sh` below covers the same intent without that dependency.

**Session-scope warning** (`session-scope-warning.sh`) — fully operational, fires on every `UserPromptSubmit`. Counts turns per session in `working/runtime/explore-scope/<session_id>.turns` and injects the same "wrap up" / "handoff now" `additionalContext` messaging as `context-warning.sh`, keyed on turn count (20, then every 20 turns past 40) instead of context %. Turn count needs no statusLine bridge, so this fires identically in Claude Code CLI and Copilot Chat.

**Exploration delegation** (`exploration-scope-guard.sh`) — fully operational, fires on `PreToolUse` for `Read`/`Grep`/`Glob`/`Task`. `skills/explore/SKILL.md` recommends delegating deep exploration to a subagent, but that guidance is prose only — nothing previously enforced it. This hook counts consecutive raw exploration calls per session in `working/runtime/explore-scope/<session_id>.count` and injects a reminder every 15 calls; spawning a `Task` (subagent) resets the counter. It never blocks — exploration is legitimate work, this is a nudge at the point of habit, not a gate.

**Verified limitation (2026-07-27):** `PreCompact` never fired as a span across any of the four real Copilot Chat session logs analyzed in this repo's own audit, including one that visibly auto-compacted mid-conversation. `compaction-guard.sh` is confirmed operational in Claude Code CLI but currently provides no protection in Copilot Chat sessions — Copilot Chat's internal summarization does not appear to route through the `PreCompact` hook event at all. No fix is available yet; this is a known gap, not a resolved one.

## Customization

Edit the scripts in `~/dotfiles/hooks/` (source of truth). Changes propagate via the symlink. To add a new hook:

1. Create `hooks/your-hook.sh` (receives JSON on stdin, exits 0 or 2)
2. Add the hook entry to `.claude/settings.json`
3. Re-run `ctrl bootstrap` (or `bash ~/dotfiles/bin/bootstrap.sh`) to deploy the updated config

To disable a hook, remove its entry from `.claude/settings.json` and re-run `ctrl bootstrap`.

## Fail Modes

Every hook declares its fail mode on line 2 as `# FAIL_MODE: closed|open`.

| Mode | Meaning | When to use |
|------|---------|-------------|
| `closed` | Unhandled errors produce deny JSON — if the hook crashes, the operation is blocked | Security/correctness (secret-guard, migration-guard, git-workflow-gate) |
| `open` | Unhandled errors exit 0 — if the hook crashes, the operation proceeds | Quality/convenience (format-check, typecheck, hud-session) |

**Principle:** Hooks that prevent irreversible damage fail closed. Hooks that improve quality fail open.

**Implementation:** Fail-closed PreToolUse hooks use `trap '_fail_closed' ERR` to emit deny JSON on any error. Other fail-closed hooks (e.g., `compaction-guard.sh`) exit 2 with plain stderr text. Fail-open hooks use `trap 'exit 0' ERR` to ensure any unhandled error exits cleanly without blocking.

## Per-Repo Config

The `git-workflow-gate.sh` hook reads an optional `.ctrlshft` YAML file at the repo root for per-repo overrides:

```yaml
# .ctrlshft — per-repo hook configuration (block-list format)
commit_types:
  - feat
  - fix
  - refactor
  - chore
  - docs
  - test
  - perf
  - ci

protected_branches:
  - main
  - master
  - production
```

> **Note:** Use YAML block-list format (one `- item` per line). Inline arrays (`[feat, fix, ...]`) are not supported by the parser.

If the file doesn't exist, defaults apply. If parsing fails, defaults apply (fail-open for config).

### Commit Message Validation

The conventional commit check in `git-workflow-gate.sh` only validates messages passed inline via the `-m` flag (e.g., `git commit -m "feat: ..."`). Editor-based commits (no `-m` flag) or commits using `-F`/`--file` are **not** validated — the message content isn't visible in the command string. This is a known limitation; linting all commit messages requires a native `commit-msg` git hook.
