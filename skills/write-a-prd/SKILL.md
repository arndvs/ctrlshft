---
description: "Write a Product Requirements Document from a rough idea. Use when asked to 'write a PRD', 'create a PRD', 'plan a feature', or when starting a new feature that needs scoping."
---

# Write a PRD

## Process

1. Ask the user for a detailed description of the problem they want to solve. Let them be vague — your job is to extract clarity.

2. Explore the codebase to understand the existing architecture, conventions, data models, and relevant code paths.

3. Interview the user relentlessly about every aspect of this plan until reaching a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer. Ask questions one at a time. If a question can be answered by exploring the codebase, explore the codebase instead.

4. Once you have a complete understanding of the problem and solution, use the template below to write the PRD. The PRD should be submitted as a GitHub issue.

## PRD Template

```markdown
# [Feature Name]

## Problem Statement

[What problem are we solving? Who has this problem? Why does it matter?]

## Solution

[High-level description of the approach]

## User Stories

1. [As a ____, I want ____ so that ____]
2. ...

## Implementation Decisions

### Modules

[Break down into logical modules/components]

### Technical Decisions

[Key architectural choices, libraries, patterns]

### Schema Changes

[Database migrations, new tables/columns, API changes]

## Testing

[What needs to be tested and how]

## Out of Scope

[Explicitly list what this PRD does NOT cover]

## Further Notes

[Anything else relevant — edge cases, open questions, future considerations]
```
