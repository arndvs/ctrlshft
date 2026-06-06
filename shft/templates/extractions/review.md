# Extraction: Review

Extract the code review findings from the agent's review output.

## Instructions

Read the agent's full output above. The agent performed a code review on a pull request. Extract:

1. **Summary** — the overall review summary
2. **Inline comments** — findings anchored to specific file paths and line numbers
3. **Replies** — responses to existing unresolved review threads

## Output

Emit a single `<output>` block. Valid JSON, field names exact.

<output>
{
  "summary": "Overall review summary",
  "inlineComments": [],
  "replies": []
}
</output>
