# TASK

You are updating branch `{{BRANCH}}` to incorporate the latest changes from the base branch.

Your job is to rebase or merge the base branch into the feature branch, resolve any conflicts, and verify the result compiles and passes tests.

# CONTEXT

<branch-info>

Feature branch: `{{BRANCH}}`

!`git log --oneline {{BRANCH}} --not $(git merge-base {{BRANCH}} HEAD) 2>/dev/null | head -20 || echo "(Could not determine branch commits)"`

</branch-info>

<pr-info>

!`gh pr view {{PR_NUMBER}} --json title,body 2>/dev/null || echo "(No linked PR)"`

</pr-info>

# INSTRUCTIONS

1. Determine the best strategy:
   - **Rebase** — preferred when the branch has a clean, linear history and few commits.
   - **Merge** — preferred when the branch has many commits or rebase would be complex.

2. Execute the update:
   ```
   # Rebase strategy
   git checkout {{BRANCH}}
   git rebase <base-branch>

   # OR merge strategy
   git checkout {{BRANCH}}
   git merge <base-branch> --no-edit
   ```

3. If conflicts occur:
   - Resolve them based on the intent of both changes.
   - Stage resolved files with `git add`.
   - Continue with `git rebase --continue` or `git commit --no-edit`.

4. After updating, run the project's test and typecheck scripts.

5. If tests fail, attempt to fix the issue. If unfixable, report it in the output.

# OUTPUT

Emit a single `<output>` block as the **last thing** in your response. Valid JSON, field names exact.

## Example

<output>
{
  "strategy": "rebase",
  "success": true,
  "conflictsResolved": ["src/lib/config.ts", "src/api/handler.ts"],
  "conflictsRemaining": [],
  "commitSha": "abc1234"
}
</output>

## Failed update

<output>
{
  "strategy": "merge",
  "success": false,
  "conflictsResolved": ["src/lib/config.ts"],
  "conflictsRemaining": ["src/api/handler.ts"],
  "commitSha": null
}
</output>

## Field reference

| Field                | Type    | Required | Notes                                                      |
| -------------------- | ------- | -------- | ---------------------------------------------------------- |
| `strategy`           | string  | **yes**  | One of: `rebase`, `merge`.                                 |
| `success`            | boolean | **yes**  | Whether the update completed without remaining conflicts.  |
| `conflictsResolved`  | array   | no       | File paths where conflicts were resolved.                  |
| `conflictsRemaining` | array   | no       | File paths where conflicts remain (only if success=false). |
| `commitSha`          | string  | no       | SHA of the final commit after update. Null if failed.      |

Do not add fields not listed above.
