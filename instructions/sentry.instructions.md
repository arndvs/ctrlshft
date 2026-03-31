# Sentry Instructions

Output "Read Sentry instructions." to chat to acknowledge you read this file.

## MCP Server Setup

Always verify the Sentry MCP server is running before any Sentry task. The server URL is:
`https://mcp.sentry.dev/mcp`

If tools are unavailable, prompt the user to connect/enable the Sentry MCP server in their Claude settings.

## Available Tools

| Tool                 | Purpose                                                 |
| -------------------- | ------------------------------------------------------- |
| `whoami`             | Verify authentication and current user                  |
| `find_organizations` | List accessible Sentry orgs                             |
| `find_teams`         | List teams within an org                                |
| `find_projects`      | List projects within an org                             |
| `find_issues`        | Search/filter issues by project, status, assignee, etc. |
| `get_issue_details`  | Deep-dive on a specific issue with full stack trace     |
| `find_releases`      | List releases for a project                             |
| `find_tags`          | Discover available tag keys for filtering               |

_(Plus additional tools for updating issues, creating comments, etc.)_

## Authentication Check

Always start a Sentry session by calling `whoami` to confirm the connection is authenticated and to identify the active user/org context.

## Key Concepts

- **Organization slug**: Required for most calls — fetch once with `find_organizations` and reuse
- **Project slug**: Scoped under an org — fetch with `find_projects`
- **Issue ID**: The numeric or short ID of a Sentry issue (e.g. `PROJECT-123`)
- **DSN**: Project-specific key used in SDK config — find in Project Settings → Client Keys

## Extracting IDs from URLs

- Issue: `https://sentry.io/organizations/{org-slug}/issues/{ISSUE_ID}/`
- Project: `https://sentry.io/organizations/{org-slug}/projects/{project-slug}/`

## Common Workflows

**Investigate an error:**

1. `whoami` → confirm auth
2. `find_organizations` → get org slug
3. `find_issues` with query filters (e.g. `is:unresolved`, tag filters)
4. `get_issue_details` → full stack trace, breadcrumbs, event context

**Triage a spike:**

1. `find_issues` filtered by `times_seen` or `firstSeen`/`lastSeen`
2. Cross-reference with `find_releases` to correlate with a deploy

## Tips

- Prefer `find_issues` with a specific `query` string (same syntax as Sentry's search bar) to narrow results before fetching details
- Use `find_tags` to discover filterable dimensions on a project before constructing queries
- Issue counts and trends are in `find_issues` — don't fetch individual events unless you need the stack trace
