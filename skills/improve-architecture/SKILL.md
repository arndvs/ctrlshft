---
name: improve-architecture
description: "Explore the codebase for architectural improvements using deep module analysis. Use when asked to 'improve architecture', 'improve codebase', 'find shallow modules', 'refactor architecture', or for periodic codebase health checks."
---

# Improve Codebase Architecture

Output "Read Improve Codebase Architecture skill." to chat to acknowledge you read this file.

A deep module has a small interface hiding a large implementation. This skill finds opportunities to deepen your codebase.

## Process

### 1. Explore

Use subagents to explore the codebase organically. Note where you experience friction:

- Where does understanding one concept require bouncing between multiple small files?
- Where are modules so shallow that the interface is nearly as complex as the implementation?
- Where have pure functions been extracted just for testability, but the real bugs hide in how they're called?
- Where do tightly coupled modules create integration risk at the seams between them?

### 2. Present Candidates

Present 3-5 clusters of shallow modules that should be deepened. For each candidate, explain:

- Which files/modules are involved
- Why they're coupled together
- What friction they create

Do not propose interface designs yet. Let the user pick which candidate to explore.

### 3. Design Multiple Interfaces

Once the user picks a candidate, spawn multiple subagents in parallel. Each should produce a radically different interface design for the deepened module. Aim for 3 diverse options that trade off complexity, testability, and caller convenience differently.

### 4. Recommend

Present all designs. Recommend which design is strongest and why. If elements from different designs combine well, propose a hybrid.

### 5. Create RFC

Once the user accepts a design, create a GitHub issue as a refactor RFC describing the current state, proposed interface, migration path, and affected files.
