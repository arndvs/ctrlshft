# TASK

You are reviewing GitHub issue #{{ISSUE_NUMBER}} for clarity, feasibility, and completeness before implementation begins.

# CONTEXT

<issue>

!`gh issue view {{ISSUE_NUMBER}} --json title,body,labels`

</issue>

# INSTRUCTIONS

1. Read the issue carefully.
2. Assess the following:
   - **Clarity** — Is the description specific enough to implement without guessing? Are acceptance criteria testable?
   - **Scope** — Is this a single, focused piece of work? Should it be split?
   - **Feasibility** — Does the codebase support what's being asked? Are there dependencies or blockers?
   - **Missing context** — Are there edge cases, error scenarios, or integration points not addressed?
3. If the issue is clear and ready, post a comment confirming it's ready for implementation.
4. If the issue needs work, post a comment with specific questions or suggestions.
5. When done, output <promise>COMPLETE</promise>

# RULES

- Be constructive — suggest improvements, don't just list problems.
- If the issue references other issues or PRDs, read those too for context.
- Do not modify any code. This is a review, not an implementation pass.
- Post your review as a single, well-structured GitHub issue comment.
