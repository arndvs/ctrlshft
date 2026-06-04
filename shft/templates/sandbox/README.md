# Docker Sandbox Template

The Dockerfile in this directory builds an agent sandbox image — a long-lived container where Claude Code runs inside a disposable environment with read-write access to a git worktree.

## Quick start

```bash
# Build the image
docker build -t sandcastle-sandbox .sandcastle/sandbox/

# Run (bind-mount your worktree)
docker run -d --name agent-sandbox \
  -v "$(pwd):/home/agent/workspace" \
  -w /home/agent/workspace \
  sandcastle-sandbox
```

## Package manager

The Dockerfile defaults to npm. To use pnpm or yarn, uncomment the relevant `corepack` block and comment out the npm section.

## How it works

1. The engine creates a git worktree for the agent's branch
2. The worktree is bind-mounted at `/home/agent/workspace`
3. Claude Code runs inside the container with full filesystem access
4. On completion, the engine copies results out and cleans up

## Opting in

Pass `--sandbox docker` when running `init-sandcastle` to copy this template into your repo's `.sandcastle/sandbox/` directory. The engine workflows will detect the Dockerfile and use container-based execution.

## Customization

Add project-specific dependencies to the Dockerfile after the base setup. For example:

```dockerfile
# Install Python (for ML projects)
USER root
RUN apt-get update && apt-get install -y python3 python3-pip && rm -rf /var/lib/apt/lists/*
USER agent
```

Keep the `ENTRYPOINT ["sleep", "infinity"]` — the engine exec's into the running container rather than replacing the entrypoint.
