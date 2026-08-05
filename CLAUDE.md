# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a containerized development environment (`mcfedr/agents`) that bundles multiple AI coding assistants (Claude CLI, Gemini CLI, OpenAI Codex) and general development tools into a single Alpine Linux Docker image. The `agents` script launches an interactive zsh shell inside the container with host credentials and the current working directory mounted in.

## Build and Run

```bash
make build      # Build the Docker image as mcfedr/agents
make install    # Symlink the agents script to ~/.local/bin/agents
agents          # Launch the containerized environment (from any directory)
```

There are no tests, linters, or CI pipelines in this project.

## Architecture

The project has five files:

- **Dockerfile** - Alpine 3 image installing system packages (Node.js, Python, Go, AWS CLI, database clients, etc.), then AI CLI tools (Claude, Gemini, Codex), shell utilities (starship, atuin, fnm, direnv), and finally configuring a non-root `agent` user with zsh.
- **agents** - Zsh script that `exec docker run`s the image with volume mounts for the current directory (delegated), credentials (SSH, git, npm, netrc as read-only), cloud configs (AWS, GitHub CLI, GitLab CLI, Atlassian CLI), and tool state directories (`.claude_agents`, `.codex_agents`). Passes through iTerm2 and terminal environment variables. Requires `SYS_ADMIN` capability and unconfined seccomp for bubblewrap sandboxing.
- **chrome-devtools-mcp-host** - Wrapper (installed to `/usr/local/bin`) that runs `chrome-devtools-mcp` against a Chrome running on the *host*. It first starts a `socat` bridge on the container's `127.0.0.1:9222` forwarding to `host.docker.internal:9222`, so the MCP connects via a loopback/IP Host header (Chrome rejects other Host headers as DNS-rebinding). Register it inside the container with `claude mcp add chrome-devtools --scope user -- chrome-devtools-mcp-host`.
- **tab_color.zsh** - iTerm2 tab color helper using `precmd_functions` hook; color is set via `IT2_TAB_COLOR` env var (defaults to red `#FF0000` inside the container via `/.envrc`).
- **Makefile** - Two targets: `build` and `install`.

## Key Design Decisions

- Credentials are mounted read-only where possible; mutable state dirs (`.claude_agents`, `.codex_agents`, `.aws_agents`, atuin history) use separate host paths to avoid polluting the user's native tool configs.
- The container uses `--cap-add=SYS_ADMIN --security-opt seccomp=unconfined` because Claude CLI uses bubblewrap (`bwrap`) for sandboxing.
- `USE_BUILTIN_RIPGREP=0` is set so Claude CLI uses the system-installed ripgrep rather than its bundled copy.
- fnm is configured with `FNM_COREPACK_ENABLED=true` for automatic Node version management with corepack support.
