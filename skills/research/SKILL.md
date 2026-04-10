---
name: research
description: "Cache expensive exploration into a research document before building. Use when asked to 'research', 'investigate before building', 'gather context', 'flush unknowns', or before a large feature where unknowns need flushing."
---

# Research

Output "Read Research skill." to chat to acknowledge you read this file.

Cache expensive exploration into a persistent research.md so implementation conversations can start with full context instead of re-exploring.

## When to Use

- Before a large feature where architecture, dependencies, or API choices are unclear
- When multiple conversations will work on the same area
- When exploration would consume >20% of context and you still need room to implement
- When the user says "research this first" or "investigate before building"

## Process

### 1. Check for Existing Research

If research.md already exists in the project root:

- Read it fully
- Check the `Generated` date in the header
- If <7 days old and topic matches: use it as-is, skip to handoff
- If >7 days old or topic doesn't match: re-validate by spot-checking 2-3 key claims, then update or regenerate

### 2. Decompose

Break the research topic into 3-6 distinct areas of concern. Each area should be explorable independently.

### 3. Parallel Exploration

Spawn a dedicated sub-agent for each area using the `explore` verb (per the explore skill). Each sub-agent should have a narrow, specific focus.

### 4. Synthesize

Combine all sub-agent findings into research.md in the project root with this structure:

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
2. /do-work — start implementing with research.md as context
3. Continue exploring — spawn additional sub-agents for open questions

## Lifecycle Management

- research.md lives in the project root
- When passing to a new conversation, always include research.md
- If a `working/*-plan.md` exists, the pickup command should include both: `@research.md @working/<plan-name>.md — pick up on remaining slices. Start with Slice [N].`
- If research.md is >7 days old, re-validate before relying on it
- If the codebase has changed significantly (major refactor, new dependencies), regenerate
- Delete research.md after the feature ships — it's a working document, not permanent docs
