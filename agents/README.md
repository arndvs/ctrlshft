# Agents

Subagent personas for Claude Code. Each `.md` file defines a specialized agent with its own system prompt, tool restrictions, model, and memory settings. Bootstrap symlinks this directory to `~/.claude/agents/`.

## Model Selection Guide

Agents come in model variants. Choose based on the task's complexity and cost sensitivity.

| Model      | Cost    | Reasoning      | Best for                                                                       |
| ---------- | ------- | -------------- | ------------------------------------------------------------------------------ |
| **Haiku**  | Lowest  | Fast, shallow  | Bulk file scanning, simple lookups, repetitive tasks                           |
| **Sonnet** | Medium  | Good general   | Day-to-day reviews, standard research, most tasks                              |
| **Opus**   | Highest | Deep, thorough | Architecture analysis, security-critical reviews, complex cross-system tracing |

**Default:** All base agents use Sonnet — the best cost/quality balance for general work.

## Agent Inventory

### Researchers

| Agent              | Model  | When to use                                                               |
| ------------------ | ------ | ------------------------------------------------------------------------- |
| `researcher`       | Sonnet | Default. General codebase exploration and architecture mapping            |
| `researcher-opus`  | Opus   | Complex cross-system data flows, architecture decisions with broad impact |
| `researcher-haiku` | Haiku  | Quick lookups, bulk file scanning, simple pattern searches                |

### Code Reviewers

| Agent                | Model  | When to use                                                               |
| -------------------- | ------ | ------------------------------------------------------------------------- |
| `code-reviewer`      | Sonnet | Default. Standard PR reviews, bug checks                                  |
| `code-reviewer-opus` | Opus   | Security-critical code, pre-deploy reviews, complex architectural changes |

### Security

| Agent              | Model  | When to use                                                   |
| ------------------ | ------ | ------------------------------------------------------------- |
| `security-auditor` | Sonnet | OWASP Top 10 scans, secrets exposure checks, config hardening |

## Platform Limitations

**Runtime model injection is not supported.** Neither `search_subagent` nor `runSubagent` accepts a model parameter at call time. Model selection is static:

- **Claude Code agents** (`agents/*.md`): Set via `model:` in YAML frontmatter. Create a new variant file to change models.
- **VS Code explore sub-agents**: Controlled globally via `chat.exploreAgent.defaultModel` in settings.json. Cannot be changed per-call.
- **MCP server sampling**: Controlled via `chat.mcp.serverSampling` allowlists per MCP server.

To benchmark the same task across models, run it once with each agent variant and compare results.

## Adding New Agents

Create `agents/your-agent.md` with this frontmatter:

```yaml
---
name: your-agent
description: One-sentence description of when this agent should be used.
tools: Read, Grep, Glob, Bash
model: sonnet
memory: user
---
```

Bootstrap picks up new files automatically — no config changes needed.

## Memory

All agents use `memory: user` — they persist learnings to agent memory across sessions. This means a code-reviewer that discovers a project's testing patterns will remember them next time.
