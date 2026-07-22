---
name: research
description: "Cache expensive exploration into a research document before building. Use when asked to 'research', 'investigate before building', 'gather context', 'flush unknowns', or before a large feature where unknowns need flushing."
---

# Research

If running interactively (human present), output "Read Research skill." to acknowledge. If running with --dangerously-skip-permissions (AFK/unattended), skip acknowledgement and proceed directly.

Cache expensive exploration into a persistent `working/research/<topic>.md` so implementation conversations can start with full context instead of re-exploring.

## When to Use

- Before a large feature where architecture, dependencies, or API choices are unclear
- When multiple conversations will work on the same area
- When exploration would consume >20% of context and you still need room to implement
- When the user says "research this first" or "investigate before building"

## Process

### 1. Check for Existing Research

If `working/research/<topic>.md` already exists:

- Read it fully
- Check the `Generated` date in the header
- If <7 days old and topic matches: use it as-is, skip to handoff
- If >7 days old or topic doesn't match: re-validate by spot-checking 2-3 key claims, then update or regenerate

### 2. Decompose

Break the research topic into 3-6 distinct areas of concern. Each area should be explorable independently.

### 3. Parallel Exploration

Spawn a dedicated sub-agent for each area using the `explore` verb (per the explore skill). Each sub-agent should have a narrow, specific focus.

### 4. Synthesize

Combine all sub-agent findings into `working/research/<topic>.md` with this structure:

```markdown
# Research: [Topic]

Generated: [date]
Topic: [one-line summary]

## Summary

[2-3 paragraph executive summary of findings]

## Architecture

[Relevant code paths, data flow, existing patterns]

## Constraints

[Technical limitations, API quirks, performance bounds, compatibility issues]

## Dependencies

[External services, libraries, APIs involved and their current state]

## Open Questions

[Unresolved decisions that need human input]

## Recommendations

[Concrete next steps based on findings]
```

### 5. Handoff

After research is complete, offer the user three paths:

1. /write-a-prd — capture findings as a formal PRD
2. /do-work — start implementing with `working/research/<topic>.md` as context
3. Continue exploring — spawn additional sub-agents for open questions

## Lifecycle Management

- Research lives in `working/research/<topic>.md` — one file per topic
- When passing to a new conversation, always include the research file in @-references
- If a `working/active/<topic>.md` plan exists, the pickup command should include both: `@working/research/<topic>.md @working/active/<topic>.md — pick up on remaining slices. Start with Slice [N].`
- If the research file is >7 days old, re-validate before relying on it
- If the codebase has changed significantly (major refactor, new dependencies), regenerate
- Delete research files after the feature ships — they're working documents, not permanent docs
- If the synthesis has lasting value beyond the immediate task, promote it to `docs/research/<topic>.md` before deleting the working copy
- See `docs/ARTIFACT-LIFECYCLE.md` for the full lifecycle
