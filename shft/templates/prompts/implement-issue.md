# TASK

You are an autonomous coding agent. Your task is to implement GitHub issue #{{ISSUE_NUMBER}}.

# CONTEXT

<issue>

!`gh issue view {{ISSUE_NUMBER}} --json title,body,labels`

</issue>

# INSTRUCTIONS

1. Read the issue details above carefully. Understand the full scope before writing code.
2. Create a branch named `{{BRANCH}}` from HEAD: `git checkout -b {{BRANCH}}`
3. Explore the codebase to understand existing architecture, conventions, and relevant code paths.
4. Implement the changes described in the issue.
5. Run the project's test and typecheck scripts before committing.
6. Commit your changes with a descriptive message referencing the issue: `Closes #{{ISSUE_NUMBER}}`.
7. When done, output <promise>COMPLETE</promise>

# RULES

- Make atomic, focused commits. Each commit should leave the codebase in a working state.
- Follow existing code conventions — read surrounding code before writing new code.
- Do not modify files unrelated to the issue.
- If the issue has acceptance criteria, verify each one before completing.
- If blocked by something outside your control, describe the blocker and output <promise>COMPLETE</promise>
