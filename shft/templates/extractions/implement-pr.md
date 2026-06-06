# Extraction: Implement PR

Extract the thread replies, new inline comments, and top-level comments from the agent's implementation output.

## Instructions

Read the agent's full output above. The agent addressed reviewer feedback on a pull request. Extract:

1. **Thread replies** — replies to existing review threads, with the exact `commentId` from the original thread
2. **New inline comments** — new comments on diff lines (not replies to existing threads)
3. **Top-level comments** — summary or cross-cutting comments for the PR conversation

## Output

Emit a single `<output>` block. Valid JSON, field names exact.

<output>
{
  "threadReplies": [],
  "newInlineComments": [],
  "topLevelComments": []
}
</output>
