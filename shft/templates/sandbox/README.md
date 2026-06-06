# Docker Sandbox

Optional Docker-based isolation for Sandcastle agent workflows.

## Usage

Set `"sandbox": "docker"` in `sandcastle.config.json` to enable.

When enabled, implementation workflows (`implement-issue`, `implement-prd`, `parallel`) run inside this container instead of directly on the host.

## Building

```bash
docker build -t sandcastle-sandbox -f .sandcastle/sandbox/Dockerfile .
```

## What's included

- Node.js 22 (LTS)
- git, curl, jq
- GitHub CLI (`gh`)

The repository is mounted at `/workspace` at runtime. Engine dependencies are installed as part of the workflow setup.

## When to use

- **CI environments** — adds isolation between agent runs
- **Untrusted code** — prevents agent-generated code from affecting the host
- **Reproducibility** — ensures consistent environment across runs

## When to skip

- **Local development** — `"sandbox": "none"` is faster and simpler
- **Simple repos** — overhead isn't worth it for small projects
