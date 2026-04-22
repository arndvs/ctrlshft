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
- When starting long-running server processes (Java servers, dev servers, etc.) from a terminal, ALWAYS redirect output to a log file AND close stdin to prevent VS Code's terminal output monitor from detecting false input prompts: `command > /tmp/server.log 2>&1 < /dev/null &`, and ALWAYS use isBackground: true. Then read the log file with `tail` or `cat` to check output
