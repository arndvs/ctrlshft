# Triage Labels

Labels used by the Sandcastle state machine. Created automatically by `ctrl init-sandcastle`.
The agent-facing contract — the two human gates, `AGENT_PAT`, and how local skills hand off to the
pipeline — is [`instructions/sandcastle-pipeline.instructions.md`](../../instructions/sandcastle-pipeline.instructions.md).

State lives on **two objects**: the **issue** carries state up to `agent:pr-open`; the **PR** carries
the review verdict (`agent:fix` / `agent:merge` / `agent:update-branch`). "Applied by" is what writes
the label; "Triggers" is the workflow the label fires (`—` = inert state marker). Chaining writes use
`AGENT_PAT`, since `GITHUB_TOKEN` label writes do not re-trigger workflows.

## State machine labels

| Label | Color | Applied by | Triggers | Next state |
|-------|-------|------------|----------|------------|
| `Sandcastle` | `#7057ff` | Human (start gate) | `agent-review-issue.yml` | `agent:review` |
| `agent:review` | `#0075ca` | `agent-review-issue.yml` *(AGENT_PAT)* | `agent-plan-issue.yml` | `agent:implement` |
| `agent:implement` | `#e4e669` | `agent-plan-issue.yml` / `agent-promote-queued.yml` / `agent-implement-prd.yml` *(AGENT_PAT)* | `agent-implement-issue.yml` | `agent:pr-open` |
| `agent:pr-open` | `#1d76db` | `agent-implement-issue.yml` | — | Verdict gate on the PR |
| `agent:fix` | `#d93f0b` | Human (verdict gate, on PR) | `agent-fix-pr-feedback.yml` | PR re-reviewed |
| `agent:merge` | `#0e8a16` | Human (verdict gate, on PR) | `agent-merge-pr.yml` | Issue closed |
| `agent:update-branch` | `#5319e7` | Human (on PR) | `agent-update-branch.yml` | Branch updated |
| `agent:implement-prd` | `#d4c5f9` | Human / `agent-implement-prd.yml` *(AGENT_PAT)* | `agent-implement-prd.yml` | `agent:implement-prd` (sub-issues remain) / `agent:review` (PR ready) / `agent:implement` |
| `agent:queued` | `#c5def5` | Human / skills (e.g. prd-to-issues) | `agent-promote-queued.yml` (on blocker close) | `agent:implement` when deps clear |
| `agent:in-progress` | `#fbca04` | Any active workflow | — | Removed on completion |
| `agent:blocked` | `#b60205` | Any workflow (on failure) | — | Human intervention |

There is no separate planning-state label — `agent-plan-issue.yml` promotes `agent:review` → `agent:implement`
directly.

## Source labels

| Label | Color | Purpose |
|-------|-------|---------|
| `source:architecture-review` | `#5319e7` | PRDs proposed by automated architecture review |
| `source:keep-tests-tight` | `#1d76db` | Test-trim PRs opened by the automated keep-tests-tight workflow |
| `repo-hygiene` | `#7057ff` | Backlog issues proposed by the nightly repo-hygiene workflow |
| `phase-0` … `phase-5` | `#c5def5` | Repo-hygiene phase markers (which phase the task belongs to) |

## State transitions

```
Human applies "Sandcastle" (start gate)
  → agent-review-issue.yml       → agent:review
    → agent-plan-issue.yml       → agent:implement
      → agent-implement-issue.yml → agent:pr-open   (PR opened; issue awaits the verdict gate)

Verdict gate — human applies one of these to the PR:
  agent:fix    → agent-fix-pr-feedback.yml  → pushes fixes, PR re-reviewed (repeat as needed)
  agent:merge  → agent-merge-pr.yml         → PR merged → issue closed

On issue close:
  agent-promote-queued.yml → each agent:queued dependent whose native blockers are all closed
                           → agent:implement

At any point:
  → agent:blocked (failure / needs human input)
  → agent:queued  (waiting for native blocking dependencies to close)
```

## Label creation

Labels are defined in `shft/templates/labels.json` and created by `init-sandcastle.sh` via the `gh label create` CLI. Existing labels are skipped (idempotent).

## AGENT_PAT requirement

Label changes made by `GITHUB_TOKEN` don't trigger other workflows (GitHub security constraint). For the full state machine chain to work, workflows that change labels require `AGENT_PAT` — a Personal Access Token with `repo` scope for private repositories or equivalent issue/PR/content scopes for fine-grained tokens.
