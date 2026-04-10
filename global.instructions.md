<!-- global.instructions.md — Universal agent rules loaded for every workspace.
     Referenced by CLAUDE.md via @~/dotfiles/global.instructions.md.
     Always loaded regardless of ACTIVE_CONTEXTS. -->

Output "Read global instructions." to chat to acknowledge your read this file.

<general>
- ALWAYS follow all rules below carefully & to the letter
- Read entire file contents instead many small chunk reads
- Always write the most proper, cleanest, DRY (Dont Repeat Yourself), bug free, fully functional and production-worthy code
- Leave NO todo’s, placeholders or missing pieces
- Include all required imports, and ensure proper naming of key components
- Keep it simple, lean, reuse what we have. Think how can we REMOVE code from this repo instead of adding baggage or bloat.
- Use early returns whenever possible to make the code more readable
- Use fast and type-safe design principles that throw errors
- Never change website copy unless told to
- Do not add legacy or backward compatibility except for database migrations
- Never fail silently. Always add strict validation. Always throw an error if something is missing or unexpected
- Never use sample data, placeholders, || or ?? fallbacks
- Never add a defensive fix using a fallback
- If front-end or back-end get an unexpected response, print the raw response to help me debug
- Before using any CSS variable, class, JS function, or utility, verify it actually exists in the codebase. Search for its definition first — never assume a name exists based on convention or naming patterns
- When reorganizing or moving elements, check and fix spacing
- When adding objects such as routes, models, stylesheets, scripts, utils etc. always read a sample existing route to learn about our design patterns and follow them
- Before changing any shared method, class, or convention, always scan for all existing usages first to understand the established pattern, then follow it consistently
- Never change my AI model, its context window, settings, URL or API keys unless explicitly told to do so
- If I ask you for a refactor or lack specificity, ask follow up questions. Think "What’s wrong with this plan?", "What I am missing?"
- Use modern APIs and patterns over legacy approaches. Baseline browser support is February 2026
- When I upload an image for you, describe it with pixel perfect accuracy and aim to replicate it perfectly as close to the image as possible
- Don't hide functionality in methods appearing as getters or checks.
- Create skills in ~/dotfiles/skills/ (symlinked to ~/.claude/skills). Local skills go in ~/dotfiles/skills/_local/ (gitignored)
- For longer operations or migrations, keep scratchdisks, temp data or progress file in a working/ directory in root folder to prevent losing them when the conversation gets compacted. Write long terminal scripts to a temp file in working/ dir with `create_file` first, then execute it with a simple one-line command
- Never inline multi-line content or text containing quotes in terminal commands. VS Code's `sendText()` corrupts heredocs over ~700 chars and zsh gets stuck in `dquote>` on unmatched quotes. Instead: use `create_file` to write the content to a temp file (e.g. /tmp/body.txt), then either run the file directly or write a small Python wrapper to /tmp/ that reads the file and passes it via subprocess. This covers heredocs, inline scripts, and CLI arguments like `--body "..."`.
- NEVER print credentials: Not in logs, not in error messages, not in agent outputs.
- All secrets and API keys live in environment variables sourced from ~/dotfiles/secrets/.env.agent (non-sensitive config) or ~/dotfiles/secrets/.env.secrets (credentials, process-scoped). NEVER hardcode secrets in skill files, config files, scripts, terminal commands, or chat output. Use os.getenv() in Python, process.env in Node, $VAR in bash. If a required env var is missing, throw an error naming the var and pointing to the appropriate .example file for setup.
- When creating or editing scripts that need credentials (API keys, tokens, passwords), those secrets are in .env.secrets and only available at runtime via `~/dotfiles/bin/run-with-secrets.sh <command>`. Non-sensitive config (usernames, hosts, spreadsheet IDs) is in the shell environment from .env.agent. Never read secrets from files directly — use os.getenv() and rely on the run-with-secrets.sh wrapper to inject them.
- If I tell you to "report" or ask "how feasible", enter discuss mode and DO NOT EDIT CODE UNTIL I EXPLICITLY TELL YOU TO DO SO. Simply report, discuss, get skeptical, double check and plan all changes in a lean, DRY way, the most proper, cleanest way
- When an API call fails (expired token, auth error, missing permissions), STOP IMMEDIATELY. Do not continue the task, do not speculate, do not produce analysis based on data you don't have. Tell me the exact error, which token/key needs updating and in which file, then wait for me to fix it before continuing
- After your are done, remove unused imports, scan for DRY violations, broken code, hidden bugs, overengineering, edge cases, your last code changes not being reflected everywhere else in the app
- When starting long-running server processes (Java servers, dev servers, etc.) from a terminal, ALWAYS redirect output to a log file AND close stdin to prevent VS Code's terminal output monitor from detecting false input prompts: `command > /tmp/server.log 2>&1 < /dev/null &`, and ALWAYS use isBackground: true. Then read the log file with `tail` or `cat` to check output
- Prefer clearing context and starting fresh over compacting. Repeated compaction leaves sediment — each round loses nuance and accumulates errors. When context is high, commit and start a new conversation

</general>

<skill-context>
If the ACTIVE_CONTEXTS environment variable is set (by ~/dotfiles/bin/detect-context.sh), use it as the authoritative context list. Otherwise, check the workspace for file signatures (next.config.*, composer.json, sanity.config.*, prisma/schema.prisma, etc.) before loading domain-specific skills. Do not load skills irrelevant to the current workspace context.
</skill-context>

<skill-self-learning>
This section covers two triggers: automatic self-learning after tasks, and explicit "remember" commands from the user.

**Trigger 1 — After completing any task where you loaded a SKILL.md:**
Self-evaluate: did anything go wrong, require a workaround, or behave differently than documented?
If yes, update the skill inline where the fix belongs — fix wrong instructions, add missing steps, correct parameters. Keep it DRY: integrate the new knowledge into the existing structure rather than appending to a separate section. If no suitable place exists, add a bullet to a `## Lessons Learned` section at the bottom (create if needed). Replace old bullets that a new finding supersedes.
Do NOT update for user error, transient issues (network timeout, rate limit), or findings already documented.
After updating, tell the user: "Updated [skill-name] skill: [one-sentence summary of what changed]"

**Trigger 2 — User says "remember", "save this", "add this to skill", or similar:**
Read the relevant SKILL.md in full, find the most suitable place to integrate the information in a DRY way, and edit it inline. Only fall back to `## Lessons Learned` if no better location exists. Confirm with: "Saved to [skill-name] skill: [one-sentence summary]."
</skill-self-learning>

<git>
- One logical change per commit. Never bundle unrelated fixes
- Review `git diff --staged` before committing. No debug logs or dead code
- Commit message format: `<type>(<scope>): <short description>` — types: feat, fix, refactor, chore, docs, test
- Each commit must leave the codebase working — no broken states mid-task
</git>

<handoff>
When I say "wrap up", "hand off", "fresh context", or when you notice your own outputs degrading (repeating yourself, losing track of earlier decisions, tool calls returning stale results): stop current work, commit what's done, and output a handoff block containing:
  - Current plan file path or PRD issue number
  - Research file path (research.md) if one exists
  - List of files modified this session
  - What's done vs what remains
  - Exact @-reference command to start the next conversation (see pickup command below)

**Plan persistence:** When a task spans multiple conversations, write the remaining plan to `working/` in the project root with a descriptive name: `working/<topic>-plan.md` (e.g. `working/production-docs-audit-plan.md`). Include full slice details, acceptance criteria, what's done, and what remains. This file is the handoff artifact — the next conversation starts by reading it.

**Pickup command:** Always end a handoff block with a ready-to-paste command for the next conversation:

```
@working/<plan-name>.md — pick up on remaining slices. Start with Slice [N].
```

Include any other @-references needed for context (research.md, PRD issue, key files).

**Lifecycle:** Delete plan files from `working/` after the work is complete. They're working documents, not permanent docs.

Standard forward-pass files: research.md (project root — cached exploration), working/\*-plan.md (slice tracking). research.md stays in project root for broad reuse; plans go in working/ because they're task-specific and disposable.

**Proactive nudge:** If context usage is high or you've been working for many turns, suggest wrapping up: "Context is getting high. I'd recommend wrapping up and starting a fresh conversation." Then offer to write the plan to working/ and provide the pickup command.
</handoff>

<code_formatting>

- Use 4 spaces for indentation
- Put conditions multiline. Do not wrap single if, else etc. statements. Never put the condition and body on the same line — always break after the condition: `if (x)\n    doSomething();` not `if (x) doSomething();`
- Single-line conditions without braces
- Empty line before the start of `if`, `for`, `while`, `foreach`, `try` blocks — not before continuation keywords (`else`, `else if`, `catch`, `finally`)
- Never put multiple statements on a single line inside braces. Always expand to multiple lines
  </code_formatting>

<thinking>
- You must engage in exhaustive, deep-level reasoning. Think deeply about edge cases, data integrity, and architectural consequences before writing code and after refactorings.
</thinking>
