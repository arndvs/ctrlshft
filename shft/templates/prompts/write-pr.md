# TASK

You are writing a pull request for branch `{{BRANCH}}`.

Your job is to analyze the changes on this branch, write a clear PR title and description, and suggest appropriate labels.

# CONTEXT

<branch-diff>

!`git log --oneline {{BRANCH}} --not $(git merge-base {{BRANCH}} HEAD) 2>/dev/null || echo "(Could not determine branch commits)"`

</branch-diff>

<full-diff>

!`git diff $(git merge-base {{BRANCH}} HEAD)..{{BRANCH}} 2>/dev/null || echo "(Could not compute diff)"`

</full-diff>

<existing-pr>

!`gh pr view {{PR_NUMBER}} --json title,body 2>/dev/null || echo "(No existing PR)"`

</existing-pr>

# INSTRUCTIONS

1. Read the commits and diff carefully.
2. Identify the primary purpose: new feature, bug fix, refactor, docs, etc.
3. Write a PR title:
   - Use conventional commit format: `feat:`, `fix:`, `refactor:`, `docs:`, `chore:`, `test:`
   - Keep under 72 characters
   - Be specific about what changed, not how
4. Write a PR body:
   - Start with a one-sentence summary of what this PR does and why
   - List key changes as bullet points
   - Note any breaking changes, migration steps, or things reviewers should pay attention to
   - Reference linked issues with `Closes #N` or `Relates to #N`
5. Suggest labels from the repo's label set.

# OUTPUT

Emit a single `<output>` block as the **last thing** in your response. Valid JSON, field names exact.

## Example

<output>
{
  "title": "feat(engine): add workflow dispatch registry",
  "body": "Adds a registry-based workflow dispatcher that replaces the switch-case routing in main.ts.\n\n## Changes\n\n- New `dispatch.ts` with `registerWorkflow()` and `dispatch()` functions\n- All 11 workflows registered via `register.ts`\n- `main.ts` reduced to CLI parsing + dispatch call\n\n## Notes for reviewers\n\n- The registry is a module-level Map — intentional for simplicity\n- Tests cover duplicate registration and unknown workflow errors\n\nCloses #42",
  "labels": ["enhancement", "engine"]
}
</output>

## Field reference

| Field    | Type   | Required | Notes                                                   |
| -------- | ------ | -------- | ------------------------------------------------------- |
| `title`  | string | **yes**  | PR title. Conventional commit format, max 256 chars.    |
| `body`   | string | **yes**  | PR body in markdown.                                    |
| `labels` | array  | no       | Suggested labels from the repo's existing label set.    |

Do not add fields not listed above.
