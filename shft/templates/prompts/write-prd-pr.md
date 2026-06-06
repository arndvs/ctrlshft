# TASK

You are writing a pull request for a PRD (Product Requirements Document) implementation.

The PRD is GitHub issue #{{ISSUE_NUMBER}}, implemented on branch `{{BRANCH}}`.

# CONTEXT

<prd>

!`gh issue view {{ISSUE_NUMBER}} --json title,body`

</prd>

<branch-diff>

!`git log --oneline {{BRANCH}} --not $(git merge-base {{BRANCH}} HEAD) 2>/dev/null | head -30`

</branch-diff>

<full-diff>

!`git diff --stat $(git merge-base {{BRANCH}} HEAD)..{{BRANCH}} 2>/dev/null`

</full-diff>

# INSTRUCTIONS

1. Read the PRD and the branch diff to understand the full scope of changes.
2. Write a PR that covers the entire PRD implementation:
   - Title: use conventional commit format, reference the PRD issue
   - Body: summarize all slices implemented, key decisions made, and testing done
   - Reference the PRD issue with `Closes #{{ISSUE_NUMBER}}`
3. Suggest appropriate labels.

# OUTPUT

Emit a single `<output>` block as the **last thing** in your response. Valid JSON, field names exact.

## Example

<output>
{
  "title": "feat: implement Sandcastle engine v1 (#42)",
  "body": "Implements the full Sandcastle engine as described in #42.\n\n## Slices implemented\n\n1. **Engine scaffold** — dispatcher, config loading, CLI parsing\n2. **Workflow system** — 11 workflows with structured output validation\n3. **Template system** — prompts, extractions, workflow YAMLs\n\n## Key decisions\n\n- Used registry pattern for workflow dispatch\n- Extraction phase runs as a second agent pass\n\n## Testing\n\n- 13 unit tests, all passing\n- Typecheck clean\n\nCloses #42",
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
