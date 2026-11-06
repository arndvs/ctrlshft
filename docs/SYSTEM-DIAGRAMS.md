# System diagrams

How ctrl+shft keeps coding agents consistent, safe and observable, in six diagrams. Each one links to the files that implement it. For the folder-level map, see [ARCHITECTURE.md](ARCHITECTURE.md). For the planning pipeline and the Sandcastle label workflow, see the [README](../README.md).

1. [Defense in depth](#1-defense-in-depth): what stands between an agent and a bad change
2. [Context loading](#2-context-loading): only the rules that match the project
3. [Guardrail hooks](#3-guardrail-hooks): which hook fires on which event
4. [Secrets](#4-secrets): config the agent can see, credentials it never can
5. [The AFK loop](#5-the-afk-loop): one iteration, start to finish
6. [Sandcastle](#6-sandcastle): the same loop in GitHub Actions, with two human gates

---

## 1. Defense in depth

No single layer is trusted on its own. Instructions shape what the agent tries; hooks block what it shouldn't do; the sandbox and short-lived tokens limit what a mistake can reach; tests and a human decide what merges.

```mermaid
flowchart LR
    A(["Agent proposes an action"]) --> L1["1. Instructions and rules<br/>loaded for this stack only"]
    L1 --> L2["2. Hooks<br/>exit 2 blocks the tool call"]
    L2 --> L3["3. Sandbox<br/>srt container in AFK mode"]
    L3 --> L4["4. Credentials<br/>per-iteration token, ~1h"]
    L4 --> L5["5. Tests and CI<br/>test-gate blocks failing commits"]
    L5 --> L6["6. Human verdict<br/>no auto-merge"]
    L6 --> M(["Change lands"])
```

| Layer | Files |
|---|---|
| Instructions and rules | [`global.instructions.md`](../global.instructions.md), [`instructions/`](../instructions/), [`rules/`](../rules/), [`bin/detect-context.sh`](../bin/detect-context.sh) |
| Hooks | [`hooks/`](../hooks/), registered in [`hooks/settings-hooks.json`](../hooks/settings-hooks.json) |
| Sandbox | [`shft/afk.sh`](../shft/afk.sh) runs `srt claude` |
| Credentials | [`bin/run-with-secrets.sh`](../bin/run-with-secrets.sh), [`bin/mint_github_app_token.py`](../bin/mint_github_app_token.py), [`secrets/README.md`](../secrets/README.md) |
| Tests and CI | [`hooks/test-gate.sh`](../hooks/test-gate.sh), [`test/hooks/`](../test/hooks/) |
| Human verdict | Sandcastle's verdict labels, section 6 |

---

## 2. Context loading

Every session starts with the same small global file. Everything else loads only when it applies, which keeps unrelated rules out of the context window and cuts the tokens spent on them.

```mermaid
flowchart TD
    OPEN(["Editor opens a project"]) --> G["CLAUDE.md, generated from CLAUDE.base.md<br/>+ global.instructions.md<br/>always loaded"]
    G --> D["bin/detect-context.sh<br/>scans file signatures:<br/>next.config.*, package.json deps,<br/>Gemfile, composer.json, ..."]
    D --> AC["ACTIVE_CONTEXTS<br/>e.g. general,nextjs,node,typescript,sanity"]
    AC --> I["instructions/*.md<br/>only the matching stacks"]
    I --> R["rules/<br/>scoped by a paths: frontmatter,<br/>load only when matching files are touched"]
    R --> S["skills/<br/>auto-discovered, loaded on demand<br/>when the task matches"]
    S --> SUB["agents/<br/>subagent personas with<br/>isolated context, read-only tools"]

    G -. "context ~95% full" .-> H["compaction-guard.sh blocks auto-compaction;<br/>the agent writes its plan to working/<br/>and a fresh session continues from it"]
```

Files: [`bin/detect-context.sh`](../bin/detect-context.sh), [`instructions/README.md`](../instructions/README.md), [`rules/`](../rules/), [`skills/`](../skills/), [`agents/`](../agents/), [`hooks/compaction-guard.sh`](../hooks/compaction-guard.sh).

---

## 3. Guardrail hooks

Claude Code runs these scripts at fixed points in a session. A `PreToolUse` hook that exits with code 2 blocks the tool call; exit 0 allows it. The registrations below are from [`hooks/settings-hooks.json`](../hooks/settings-hooks.json).

```mermaid
flowchart TD
    SS(["SessionStart"]) --> SS1["hud-session.sh<br/>stale-branches.sh"]
    UP(["UserPromptSubmit"]) --> UP1["session-scope-warning.sh"]

    TOOL(["Agent calls a tool"]) --> PRE{"PreToolUse"}
    PRE -- "Bash" --> B["secret-guard.sh: credential exposure<br/>migration-guard.sh: non-test databases<br/>git-workflow-gate.sh: main, force-push, messages<br/>plan-quality-gate.sh: scaffolding without a plan<br/>plan-review-phase2.py: PR diff vs plan<br/>test-gate.sh: commits while tests fail"]
    PRE -- "Read, Grep, Glob, Task" --> E["exploration-scope-guard.sh<br/>nudges toward a subagent<br/>after 15+ raw reads"]
    B --> V{"exit code"}
    E --> V
    V -- "0" --> RUN["Tool runs"]
    V -- "2" --> BLOCK(["Blocked, with the reason<br/>returned to the agent"])
    RUN --> POST["PostToolUse<br/>Bash: git-post-commit, git-post-push,<br/>Copilot review request on new PRs<br/>Write: feedback-memory-gate.py<br/>Read: hud-reads.sh"]

    PC(["PreCompact (auto)"]) --> PC1["compaction-guard.sh<br/>blocks at ~95%, forces the handoff"]
    ST(["Stop"]) --> ST1["format-check.sh: formats changed files<br/>typecheck.sh: blocks stopping until tsc passes"]
```

The guard hooks have regression tests in [`test/hooks/`](../test/hooks/): `secret-guard`, `migration-guard`, `git-workflow-gate`, `test-gate`, `exploration-scope-guard` and others, run by `run-hook-tests.sh`. Details and customization: [`hooks/README.md`](../hooks/README.md).

---

## 4. Secrets

Four tiers. The agent can read config, never credentials. A credential exists only inside the child process that needs it and is gone when that process exits.

```mermaid
flowchart LR
    subgraph SEE["Agent can see"]
        AG["secrets/.env.agent<br/>usernames, hosts, IDs<br/>loaded in the shell"]
    end
    subgraph NEVER["Agent never sees"]
        SEC["secrets/.env.secrets<br/>API keys, tokens, passwords"]
        BR["secrets/.env.bridge<br/>WEBHOOK_SECRET"]
        TOK["AFK iteration token<br/>GitHub App installation token,<br/>minted per loop, expires ~1h"]
    end

    SEC -- "run-with-secrets.sh --only NAMES --" --> CHILD["Child process<br/>gets only the named secrets"]
    CHILD -- "exits" --> GONE(["Secrets gone"])
    SEC -- "GitHub App key" --> MINT["mint_github_app_token.py"] --> TOK
    TOK --> ITER["One AFK iteration"]

    DENY["Deny rules + secret-guard.sh block<br/>env, printenv, cat secrets/*, echo $*KEY*"] -. "guards" .-> NEVER
```

Files: [`secrets/README.md`](../secrets/README.md), [`bin/run-with-secrets.sh`](../bin/run-with-secrets.sh), [`bin/mint_github_app_token.py`](../bin/mint_github_app_token.py), [`hooks/secret-guard.sh`](../hooks/secret-guard.sh). If a raw token is ever printed, the README's rotation steps apply.

---

## 5. The AFK loop

`shft afk` works through the GitHub issue backlog with nobody watching. Each iteration gets its own token, its own sandbox run and its own log, and the loop stops at a fixed number of iterations or when the backlog is empty.

```mermaid
flowchart TD
    START(["shft afk N<br/>default N = 5"]) --> LOCK{"mkdir lock dir"}
    LOCK -- "already exists" --> BUSY(["Exit: another loop is running"])
    LOCK -- "created" --> VAL["validate-env.sh --afk<br/>via run-with-secrets, App creds only"]
    VAL --> IT["Iteration i of N"]
    IT --> STOPQ{"lock removed?<br/>(shft stop)"}
    STOPQ -- "yes" --> END1(["Stop before this iteration"])
    STOPQ -- "no" --> MINT["Mint a GitHub App token<br/>for this iteration only"]
    MINT --> PROMPT["_build_prompt.sh<br/>issue text with XML-like tags escaped,<br/>against prompt injection"]
    PROMPT --> RUNC["srt claude --print<br/>in a container sandbox,<br/>GITHUB_TOKEN = this token only"]
    RUNC --> LOG["Stream tool calls and text;<br/>log duration and cost per iteration"]
    LOG --> DONE{"NO MORE TASKS?"}
    DONE -- "yes" --> END2(["Exit: backlog empty"])
    DONE -- "no" --> MAX{"i = N?"}
    MAX -- "no" --> IT
    MAX -- "yes" --> END3(["Exit: iteration cap reached"])
```

Files: [`shft/afk.sh`](../shft/afk.sh), [`shft/_build_prompt.sh`](../shft/_build_prompt.sh), [`shft/README.md`](../shft/README.md).

One known gap: on WSL and MSYS there's no container sandbox, so the loop runs Claude directly and prints a warning. The hooks and deny rules still apply, but there's no second layer.

---

## 6. Sandcastle

Sandcastle runs the same loop in GitHub Actions, driven by labels on issues and PRs. The engine lives once in [`ctrlshft-hub`](https://github.com/arndvs/ctrlshft-hub); each consumer repo keeps a config file, a SHA-locked hub version, and thin workflow stubs.

```mermaid
flowchart LR
    H(["Human applies<br/>the Sandcastle label"]) --> R["agent:review"]
    R --> I["agent:implement"]
    I --> P["agent:pr-open"]
    P --> V{"Human verdict"}
    V -- "agent:merge" --> M(["merge-pr"])
    V -- "agent:fix" --> F["fix-pr-feedback"]
    V -- "agent:update-branch" --> U["update-branch"]
    F --> P
    U --> P
    I -. "wrong token" .-> B(["agent:blocked<br/>fails closed"])
```

Two human gates by design: the start gate (applying the label) and the verdict gate. There is no auto-merge. Agent output is validated against schemas, and label chaining needs `AGENT_PAT`; with the wrong token the chain fails closed into `agent:blocked`. Details: the [Sandcastle section of the README](../README.md#sandcastle-autonomous-agents-in-ci) and [ADR-005](adr/ADR-005-sandcastle-agent-parity.md).
