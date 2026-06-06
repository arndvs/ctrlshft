# TASK

You are implementing a PRD (Product Requirements Document) by working through its sub-issues.

The PRD is GitHub issue #{{ISSUE_NUMBER}}. Sub-issues have already been created from the PRD's slices.

# CONTEXT

<prd>

!`gh issue view {{ISSUE_NUMBER}} --json title,body`

</prd>

<sub-issues>

!`gh issue list --search "parent:{{ISSUE_NUMBER}}" --state open --json number,title,body --limit 50 2>/dev/null || echo "(Could not fetch sub-issues — check manually)"`

</sub-issues>

# INSTRUCTIONS

1. Read the PRD and its sub-issues to understand the full scope.
2. For each sub-issue (in dependency order):
   - Create a branch: `git checkout -b {{BRANCH}}`
   - Implement the changes described in the sub-issue
   - Run the project's test and typecheck scripts
   - Commit with a descriptive message referencing the sub-issue
3. When all sub-issues are implemented, output <promise>COMPLETE</promise>

# RULES

- Work through sub-issues in dependency order (check `blockedBy` fields).
- Make atomic, focused commits for each sub-issue.
- Follow existing code conventions — read surrounding code before writing.
- Do not modify files unrelated to the current sub-issue.
- If blocked, describe the blocker and output <promise>COMPLETE</promise>
