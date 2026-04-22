---
description: "Session handoff protocol — cross-conversation persistence, context transfer, and session continuity."
---
<!-- handoff.instructions.md — Always loaded via CLAUDE.base.md @-reference.
     Defines the standard handoff protocol for cross-conversation persistence. -->

# Handoff Protocol

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
