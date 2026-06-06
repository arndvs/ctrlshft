# TASK

You are performing an architecture review of this repository.

Your job is to analyze the codebase structure, identify architectural concerns, and suggest improvements. Focus on maintainability, scalability, and correctness — not style.

# CONTEXT

<issue>

!`gh issue view {{ISSUE_NUMBER}} --json title,body 2>/dev/null || echo "(No specific issue — reviewing the full codebase)"`

</issue>

# REVIEW METHODOLOGY

## What to look for

1. **Coupling** — Modules that know too much about each other's internals. Circular dependencies. God objects.
2. **Missing abstractions** — Repeated patterns that should be extracted. Raw operations where a domain concept exists.
3. **Error handling** — Silent failures, swallowed exceptions, missing error boundaries.
4. **Data flow** — Unclear ownership of state. Data passed through too many layers. Leaky abstractions.
5. **Scalability** — O(n^2) patterns, unbounded growth, missing pagination, missing caching where needed.
6. **Security** — Hardcoded secrets, missing input validation at trust boundaries, overly permissive access.
7. **Testability** — Code that's hard to test due to tight coupling, global state, or side effects in constructors.

## Severity guide

- `critical` — Must fix before shipping. Security vulnerabilities, data loss risks, correctness bugs in core paths.
- `warning` — Should fix soon. Tech debt that compounds, performance issues under load, missing error handling.
- `info` — Worth knowing. Patterns that could improve, future risks, minor inconsistencies.

# OUTPUT

Emit a single `<output>` block as the **last thing** in your response. Valid JSON, field names exact.

## Example

<output>
{
  "findings": [
    {
      "area": "shft/engine/lib/dispatch.ts",
      "severity": "warning",
      "description": "The dispatch registry is a global mutable Map with no reset mechanism. In tests, registered workflows leak between test files.",
      "recommendation": "Accept the registry as a parameter or provide a `clearRegistry()` for test isolation."
    },
    {
      "area": "Database layer",
      "severity": "critical",
      "description": "User input is interpolated directly into SQL queries in `db/queries.ts` lines 45-60.",
      "recommendation": "Use parameterized queries. Never interpolate user input into SQL strings."
    }
  ],
  "prdSuggestions": [
    {
      "title": "Extract shared validation logic",
      "description": "Three workflows duplicate the same input validation. Extract into a shared `validateWorkflowInput()` utility."
    }
  ],
  "summary": "The architecture is generally sound with clear module boundaries. Two critical findings around SQL injection and one warning about test isolation. Suggested one PRD for shared validation extraction."
}
</output>

## Empty output

If the codebase has no issues:

<output>
{ "findings": [], "prdSuggestions": [], "summary": "No architectural concerns found." }
</output>

## Field reference

| Field                            | Type   | Required | Notes                                                              |
| -------------------------------- | ------ | -------- | ------------------------------------------------------------------ |
| `findings`                       | array  | no       | Architectural findings, ordered by severity (critical first).      |
| `findings[].area`                | string | **yes**  | File path, module name, or conceptual area.                        |
| `findings[].severity`            | string | **yes**  | One of: `critical`, `warning`, `info`.                             |
| `findings[].description`         | string | **yes**  | What the problem is.                                               |
| `findings[].recommendation`      | string | **yes**  | What to do about it.                                               |
| `prdSuggestions`                  | array  | no       | Suggested PRDs for improvements that need their own planning pass. |
| `prdSuggestions[].title`          | string | **yes**  | Short title for the suggested PRD.                                 |
| `prdSuggestions[].description`    | string | **yes**  | What the PRD should cover.                                         |
| `summary`                        | string | **yes**  | One-paragraph summary of the review.                               |

Do not add fields not listed above.
</content>
</invoke>