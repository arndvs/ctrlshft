---
name: write-a-prd
description: "Write a Product Requirements Document from a rough idea. Use when asked to 'write a PRD', 'create a PRD', 'plan a feature', or when starting a new feature that needs scoping."
---

# Write a PRD

Output "Read Write a PRD skill." to chat to acknowledge you read this file.

## Process

1. Ask the user for a detailed description of the problem they want to solve. Let them be vague — your job is to extract clarity.

2. Explore the codebase to understand the existing architecture, conventions, data models, and relevant code paths.

3. Interview the user following the grill-me skill pattern — ask questions one at a time, provide recommended answers, explore the codebase when a question can be answered by code. Focus questions on the problem domain, solution approach, edge cases, and module boundaries.

4. Sketch modules — before writing the PRD, identify the major modules to build or modify. For each module: describe its public interface (what callers see), look for opportunities to extract deep modules (thin interface hiding large implementation), and determine the test boundary (where tests should verify behavior). Confirm module boundaries with the user.

5. Once you have a complete understanding of the problem and solution, use the template below to write the PRD. The PRD should be submitted as a GitHub issue.

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

[For each module:]

- **Name**: [module name]
- **Interface**: [public API — what callers see and use]
- **Responsibility**: [what it does internally]
- **Test boundary**: [where tests verify behavior — unit, integration, or e2e]
- **Deep module opportunity**: [can the interface be simplified while keeping implementation rich?]

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
