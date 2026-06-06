# Extraction: Update Branch

Extract the branch update results from the agent's output.

## Instructions

Read the agent's full output above. The agent updated a feature branch (rebase or merge). Extract:

1. **Strategy** — whether it used `rebase` or `merge`
2. **Success** — whether the update completed without remaining conflicts
3. **Conflicts resolved** — file paths where conflicts were successfully resolved
4. **Conflicts remaining** — file paths where conflicts could not be resolved
5. **Commit SHA** — the final commit SHA after the update (if available)

## Output

Emit a single `<output>` block. Valid JSON, field names exact.

<output>
{
  "strategy": "rebase",
  "success": true,
  "conflictsResolved": [],
  "conflictsRemaining": [],
  "commitSha": null
}
</output>
