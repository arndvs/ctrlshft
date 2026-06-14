---
name: performance-audit
description: "Deep system and codebase performance audit — memory leaks, process bloat, network latency, and runtime profiling. Use when asked to 'performance audit', 'why is everything slow', 'find memory leaks', 'check system health', 'diagnose slowness', or 'perf check'."
---

# Performance Audit

Output "Read Performance Audit skill." to chat to acknowledge you read this file.

You are a senior performance engineer. Ultrathink. Perform a deep, systematic performance audit across system resources, process health, and codebase runtime behavior. Your goal is to find what's actually slow and why — not to speculate.

## When to Use

- System feels slow across multiple repos/tools
- AI agents (Copilot, Claude, Orca) are responding slowly
- Dev servers are eating memory
- VS Code is unresponsive
- Before/after deploying infrastructure changes

Pipeline position: standalone — invoke anytime as `/performance-audit` or `ctrl perf`

## Tooling

All diagnostic scripts live in `~/dotfiles/bin/perf/` and are cross-platform (Windows/macOS/Linux). They auto-detect the OS and run appropriate commands. Invoke via `ctrl perf` or directly.

| Command                        | What it does                                      |
| ------------------------------ | ------------------------------------------------- |
| `ctrl perf`                    | Full audit (triage + deep analysis)               |
| `ctrl perf triage`             | Phase 1 only (memory, processes, network, disk)   |
| `ctrl perf deep`               | Phase 2 only (VS Code, bloatware, dev servers)    |
| `ctrl perf memory`             | Memory snapshot only                              |
| `ctrl perf processes`          | Process census only                               |
| `ctrl perf network`            | API latency only                                  |
| `ctrl perf disk`               | Disk space only                                   |
| `ctrl perf proxy`              | LiteLLM proxy health only                         |
| `ctrl perf vscode`             | VS Code extension host analysis                   |
| `ctrl perf bloatware`          | OEM bloatware detection                           |
| `ctrl perf devservers`         | Dev server profiling                              |

Direct invocation:
```bash
bash ~/dotfiles/bin/perf/system-triage.sh              # Phase 1
bash ~/dotfiles/bin/perf/system-triage.sh --section memory  # single section
bash ~/dotfiles/bin/perf/deep-analysis.sh              # Phase 2
bash ~/dotfiles/bin/perf/deep-analysis.sh --section bloatware
```

## Process

### Phase 1: System Triage (always run first)

Run the triage script and collect raw data before forming any conclusions.

```bash
ctrl perf triage
```

Or run the script directly:
```bash
bash ~/dotfiles/bin/perf/system-triage.sh
```

Analyze each section of output:

#### Memory
- **System memory %** — >85% sustained = swap pressure, everything degrades
- **Private vs Working Set ratio** — PrivMB >> WorkMB = leaked memory paged out
- **Handle counts** — >2000 handles on a non-system process = probable handle leak
- **Process uptime** — high memory + short uptime = fast leak; high memory + long uptime = slow accumulation

#### Processes
- **VS Code process count** — >15 per window is abnormal. 3 windows × 15 = 45 is expected but heavy
- **Duplicate language servers** — each VS Code window spawns its own set (TypeScript, Pylance, Tailwind, etc.)
- **Orphan processes** — node/python processes with no parent VS Code window
- **AI agent processes** — Orca, copilot, claude CLI instances

#### Network
- **DNS resolution time** — >500ms = DNS issue
- **TLS handshake** — >1s = network or proxy overhead
- **Total latency** — >2s to GitHub API = connectivity problem

#### Disk
- Free space <10% on system drive = performance cliff (swap, temp files, caching all degrade)

#### Proxy
- Is the proxy running? Is it healthy?
- Check proxy logs for error patterns or queue buildup

### Phase 2: Deep Analysis (targeted dives)

Only investigate areas where Phase 1 surfaced anomalies.

```bash
ctrl perf deep
```

Or target specific sections:
```bash
ctrl perf vscode       # extension host → workspace mapping
ctrl perf bloatware    # OEM service detection
ctrl perf devservers   # node process profiling
```

#### VS Code Process Tree
Maps each extension host to its workspace and lists attached language servers with memory. Cross-references with active workspaces from the last 12 hours.

#### Bloatware Detection
Scans running services against known bloatware patterns:
- **HP**: Sure Click, Touchpoint Analytics, SysInfoCap, DiagsCap
- **Dell**: SupportAssist, DellData
- **Lenovo**: Vantage, LenovoNow
- **AV bloat**: McAfee, Norton, TrendMicro, Avast
- **Telemetry**: DiagTrack, CompatTelRunner, dmwappushservice

Outputs flagged services with ready-to-paste disable commands.

#### Dev Server Profiling
Finds node processes >200 MB with uptime and command line. Red flags:
- Next.js dev server >1 GB after <5 minutes = memory leak in app code
- node process >2 GB = likely `--max-old-space-size` being hit, GC thrashing
- Multiple dev servers running for different repos simultaneously

### Phase 3: Codebase-Level Leak Hunting (agent-driven)

If a specific repo's dev server is leaking, spawn a subagent to explore:

```
Explore the [repo] codebase for memory leak patterns. Check:
- Module-level data fetches (top-level await, large static imports)
- Middleware that runs on every request and accumulates state
- unstable_cache or fetch without revalidation in dev mode
- Event listeners registered without cleanup
- Large datasets loaded into module scope
- Circular dependencies causing repeated module evaluation
```

### Phase 4: Report

Present findings in this exact format:

## CRITICAL — Actively degrading performance now

- [process/service] What's wrong, current impact (MB/handles), and fix command

## LEAKS — Memory growing over time

- [process:PID] Growth rate if observable, root cause, and remediation

## BLOATWARE — Non-essential services wasting resources

- [service] What it does, MB consumed, disable command

## NETWORK — Latency or connectivity issues

- [endpoint] Latency observed, expected baseline, likely cause

## CODEBASE — App-level performance issues in specific repos

- [repo:file] What's leaking or slow, why, and suggested fix

## RECOMMENDATIONS — Ordered by impact

1. [Highest impact action] — expected savings
2. [Next action] — expected savings
3. ...

### Savings Summary

| Category | Current | After fixes | Savings |
|----------|---------|-------------|---------|
| Memory   | X GB    | Y GB        | Z GB    |
| Processes| N       | M           | N-M     |
| Services | N       | M           | N-M     |

## HUD Events

Emit bookend events:

```bash
source ~/dotfiles/bin/write-hud-state.sh
# At start
write_hud_event "info" "performance-audit: started"
# At end
write_hud_event "info" "performance-audit: completed — N findings, ~X GB recoverable"
```

## Rules

- **Measure before concluding.** Run `ctrl perf` commands, collect numbers, then diagnose. No speculative "this might be slow."
- **Every finding must include a fix.** If you can't provide a concrete remediation, it's not actionable — skip it.
- **Severity = impact × frequency.** A 2 GB leak matters more than a 50 MB service.
- **Do not report normal system processes** (dwm, System, lsass, csrss, svchost) unless they show anomalous behavior.
- **Cross-reference uptime with memory.** A process at 500 MB after 12 hours is fine. A process at 500 MB after 2 minutes is not.
- **Provide disable/kill commands ready to paste** — the user should not have to research how to stop something you identified.

## Handoff

If context is high, follow the standard handoff protocol (`@~/dotfiles/instructions/handoff.instructions.md`). Persist findings to `working/active/performance-audit.md` with all collected data and remaining investigation areas.
