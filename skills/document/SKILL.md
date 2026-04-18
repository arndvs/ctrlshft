---
name: document
description: "Write, update, or audit documentation. Use when asked to 'document this', 'write docs', 'update the README', 'add JSDoc', 'write a changelog', 'create an ADR', or when documentation is missing or out of date."
---

# Document

Output "Read Document skill." to chat to acknowledge you read this file.

Pipeline position: can be used standalone or after `/do-work` to document what was just built.

## Role

You write accurate, minimal, audience-appropriate documentation. You do not invent behavior — you document what the code actually does. If something is unclear, you read the source before writing.

## Step 1: Establish Context

Before writing anything, determine **what** and **where**. Infer from context if possible (e.g. a JSDoc task on a TypeScript file is obvious). If not obvious, ask:

**What type of documentation?** (select all that apply)

- Code/API docs (JSDoc, inline comments)
- README / project onboarding
- Architecture decision records (ADRs)
- User-facing docs / guides
- Changelog / release notes

**Where does it live?**

- In the codebase (inline + markdown files)
- External (Notion, Gitbook, Mintlify, etc.)
- GitHub (README, wiki, releases)
- All of the above

Ask both questions in a single message. Do not ask them separately. Do not proceed until you have answers.

## Step 2: Explore Before Writing

Read the relevant source files, existing docs, and git history before writing anything. Never document from memory or assumption.

- For code docs → read the implementation, not just the interface
- For READMEs → read the codebase structure, package.json, existing README if present
- For ADRs → read the code that reflects the decision, not just the ticket
- For changelogs → read `git log` or merged PRs since last release
- For user guides → read the feature end-to-end as a user would encounter it

## Step 3: Write

### Code/API Docs

- Document the **why** not the **what** — the code already shows what
- JSDoc: include `@param`, `@returns`, `@throws` where non-obvious
- Inline comments: only for non-obvious logic. Delete comments that restate the code
- No placeholder descriptions. If you don't understand it, read more source

### README / Project Onboarding

Follow the WHY / WHAT / HOW structure:

- **WHY** — what problem does this solve and for whom
- **WHAT** — what the project is, what its major parts are
- **HOW** — how to install, run, test, and contribute

Keep it scannable. No walls of text. Prefer code blocks over prose for commands.

### Architecture Decision Records (ADRs)

Use this structure:

```

# ADR-NNN: [Title]

Date: YYYY-MM-DD
Status: Proposed | Accepted | Deprecated | Superseded by ADR-NNN

## Context

[What situation forced this decision?]

## Decision

[What was decided?]

## Consequences

[What does this make easier? What does it make harder?]

```

### User-Facing Docs / Guides

- Write for the user's goal, not the system's structure
- Task-oriented: "How to X" not "X feature overview"
- No internal jargon. No implementation detail unless the user needs it
- Include examples. Prefer working code snippets over prose descriptions

### Changelog / Release Notes

Follow Keep a Changelog format:

```

## [version] - YYYY-MM-DD

### Added

### Changed

### Fixed

### Removed

```

Read git log or merged PRs to populate. Never fabricate entries.

## Step 4: Validate

- Does every claim trace to actual code or behavior?
- Are there any TODOs, placeholders, or "TBD" entries? Remove or resolve them.
- If documenting a public API, verify the examples actually run

## Rules

**Do:**

- Read source before writing
- Document what exists, not what should exist
- Keep docs close to what they describe (prefer inline over wiki for code)
- Use the simplest structure that communicates the intent

**Do not:**

- Invent behavior or parameters
- Add docs that restate the code
- Document unimplemented features
- Use the word "straightforward", "simple", or "just"

## Handoff

If context is high before documentation is complete, follow the standard handoff protocol (global instructions `<handoff>`) — persist progress to `working/` and provide the pickup command.
