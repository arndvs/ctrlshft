# Extraction: Architecture Review

Extract the architecture review findings from the agent's analysis output.

## Instructions

Read the agent's full output above. Extract the structured findings into the JSON format below.

For each finding:
- `area`: The file path, module, or conceptual area the finding relates to
- `severity`: One of `critical`, `warning`, `info`
- `description`: What the problem is
- `recommendation`: What to do about it

For each PRD suggestion:
- `title`: Short title for the suggested work
- `description`: What the work should cover

## Output

Emit a single `<output>` block. Valid JSON, field names exact.

<output>
{
  "findings": [],
  "prdSuggestions": [],
  "summary": "One-paragraph summary"
}
</output>
