FROM node:22-bookworm

# Install system dependencies
RUN apt-get update && apt-get install -y \
  git \
  curl \
  jq \
  && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
  && apt-get update && apt-get install -y gh \
  && rm -rf /var/lib/apt/lists/*

# Uncomment ONE of the following package manager blocks:

# --- npm (default, no extra setup) ---
# npm is included with Node.js

# --- pnpm ---
# RUN corepack enable && corepack prepare pnpm@latest --activate

# --- yarn ---
# RUN corepack enable && corepack prepare yarn@stable --activate

# Rename the base image's "node" user (UID 1000) to "agent".
# Keeps UID 1000 so that --userns=keep-id (Podman) and
# --user 1000:1000 (Docker) map to the correct home directory.
RUN usermod -d /home/agent -m -l agent node
USER agent

# Install Claude Code CLI
RUN curl -fsSL --proto '=https' --tlsv1.2 https://claude.ai/install.sh -o /tmp/install-claude.sh \
  && bash /tmp/install-claude.sh \
  && rm -f /tmp/install-claude.sh

# Add Claude to PATH
ENV PATH="/home/agent/.local/bin:$PATH"

WORKDIR /home/agent

# In worktree sandbox mode, the engine bind-mounts the git worktree
# at /home/agent/workspace and overrides the working directory at start.
ENTRYPOINT ["sleep", "infinity"]
