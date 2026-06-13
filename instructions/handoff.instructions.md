---
description: "Session handoff protocol — cross-conversation persistence, context transfer, and session continuity."
---
<!-- handoff.instructions.md — Always loaded via CLAUDE.base.md @-reference.
     Defines the standard handoff protocol for cross-conversation persistence. -->

# Handoff Protocol

When I say "wrap up", "hand off", "fresh context", or when you notice your own outputs degrading (repeating yourself, losing track of earlier decisions, tool calls returning stale results): stop current work, commit what's done, and output a handoff block containing:

- Current plan file path or PRD issue number
- Research file path (`working/research/<topic>.md`) if one exists
- List of files modified this session
- What's done vs what remains
- Exact @-reference command to start the next conversation (see pickup command below)

**Plan persistence:** When a task spans multiple conversations, write the remaining plan to `working/active/<topic>.md` (e.g. `working/active/production-docs-audit.md`). Include full slice details, acceptance criteria, what's done, and what remains. This file is the handoff artifact — the next conversation starts by reading it.

**Pickup command:** Always end a handoff block with a ready-to-paste command for the next conversation:

```
@working/active/<topic>.md — pick up on remaining slices. Start with Slice [N].
```

Include any other @-references needed for context (`working/research/<topic>.md`, PRD issue, key files).

**Lifecycle:** Delete plan and research files after the work ships. They're working documents, not permanent docs. If research has lasting value beyond the task, promote it to `docs/research/`. See `docs/ARTIFACT-LIFECYCLE.md` for the full lifecycle.

Standard forward-pass files: `working/research/<topic>.md` (cached exploration), `working/active/<topic>.md` (execution tracking). Both are disposable — delete when work ships.

**Proactive nudge:** If context usage is high or you've been working for many turns, suggest wrapping up: "Context is getting high. I'd recommend wrapping up and starting a fresh conversation." Then offer to write the plan to `working/active/` and provide the pickup command.
