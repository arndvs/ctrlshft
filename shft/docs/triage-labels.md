# Triage Labels

Labels used by the Sandcastle state machine. Created automatically by `ctrl init-sandcastle`.

## State machine labels

| Label | Color | Trigger | Next state |
|-------|-------|---------|------------|
| `Sandcastle` | `#7057ff` | Human applies to issue | `agent:review` |
| `agent:review` | `#0075ca` | `agent-plan-issue.yml` | `agent:implement` |
| `agent:plan` | `#006b75` | none (state-tracking label) | `agent:implement` |
| `agent:implement` | `#e4e669` | `agent-implement-issue.yml` | `agent:pr-open` |
| `agent:pr-open` | `#1d76db` | PR opened by agent | `agent:merge` or `agent:fix` |
| `agent:fix` | `#d93f0b` | `agent-fix-pr-feedback.yml` | `agent:pr-open` |
| `agent:merge` | `#0e8a16` | `agent-merge-pr.yml` | Issue closed |
| `agent:blocked` | `#b60205` | Any workflow (on failure) | Human intervention |
| `agent:queued` | `#c5def5` | Human applies | `agent:implement` (when deps close) |
| `agent:in-progress` | `#fbca04` | Any active workflow | Removed on completion |
| `agent:update-branch` | `#5319e7` | `agent-update-branch.yml` | Branch updated |
| `agent:implement-prd` | `#d4c5f9` | `agent-implement-prd.yml` | Sub-issue created + implemented |

## Source labels

| Label | Color | Purpose |
|-------|-------|---------|
| `source:architecture-review` | `#5319e7` | PRDs proposed by automated architecture review |

## State transitions

```
Human applies "Sandcastle"
  → agent:review (review workflow gathers context)
    → agent:implement (plan workflow runs and promotes)
      → agent:pr-open (PR awaiting review)
        → agent:fix (if review comments)
          → agent:pr-open (cycle until approved)
        → agent:merge (checks pass, approved)
          → closed

At any point:
  → agent:blocked (needs human input)
  → agent:queued (waiting for dependency issues to close)
```

## Label creation

Labels are defined in `shft/templates/labels.json` and created by `init-sandcastle.sh` via the `gh label create` CLI. Existing labels are skipped (idempotent).

## AGENT_PAT requirement

Label changes made by `GITHUB_TOKEN` don't trigger other workflows (GitHub security constraint). For the full state machine chain to work, workflows that change labels require `AGENT_PAT` — a Personal Access Token with `repo` scope for private repositories or equivalent issue/PR/content scopes for fine-grained tokens.
