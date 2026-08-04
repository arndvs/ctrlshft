---
description: "Workarounds for VS Code terminal limitations — heredoc corruption, long scripts, and background server processes."
paths:
  - "**/bin/**"
  - "**/*.sh"
  - "**/*.bash"
---

# Terminal & Script Workarounds

- For longer operations or migrations, keep scratchdisks, temp data or progress files in a `working/` directory in the project root to prevent losing them when the conversation gets compacted. Write long terminal scripts to a temp file in `working/` with `create_file` first, then execute with a simple one-line command
- Never inline multi-line content or text containing quotes in terminal commands. VS Code's `sendText()` corrupts heredocs over ~700 chars and zsh gets stuck in `dquote>` on unmatched quotes. Instead: use `create_file` to write the content to a temp file (e.g. /tmp/body.txt), then either run the file directly or write a small Python wrapper to /tmp/ that reads the file and passes it via subprocess. This covers heredocs, inline scripts, and CLI arguments like `--body "..."`
- In Git Bash/MSYS on Windows, native Windows programs receive translated path-like environment variables (for example `/tmp/x` may become `C:/Users/.../Temp/x`), but string literals embedded inside inline Python are not translated. When a shell script passes a temp path to Python, pass it through an environment variable and read `os.environ[...]` inside Python; do not interpolate the raw `/tmp/...` string into Python source.
- When starting long-running server processes (Java servers, dev servers, etc.) from a terminal, ALWAYS redirect output to a log file AND close stdin to prevent VS Code's terminal output monitor from detecting false input prompts: `command > /tmp/server.log 2>&1 < /dev/null &`, and ALWAYS use isBackground: true. Then read the log file with `tail` or `cat` to check output
- Never chain `cd <dir> &&` in front of a command to change directory. Use the terminal tool's `cwd`/`cwd` parameter (or the persistent shell's existing working directory) instead. `cd &&` chains leak shell state across calls, cost an extra round trip, add wasted tokens on every invocation, and are what `git-workflow-gate.sh` blocks for git commands specifically. This applies to every command, not just git.
