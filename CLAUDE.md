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

The project has six files:

- **Dockerfile** - Alpine 3 image installing system packages (Node.js, Python, Go, AWS CLI, database clients, etc.), then AI CLI tools (Claude, Gemini, Codex), shell utilities (starship, atuin, fnm, direnv), and finally configuring a non-root `agent` user with zsh.
- **agents** - Zsh script that `exec docker run`s the image with volume mounts for the current directory (delegated), credentials (SSH, git, npm, netrc as read-only), cloud configs (AWS, gcloud, kubeconfig, GitHub CLI, GitLab CLI, Atlassian CLI), and tool state directories (`.claude_agents`, `.codex_agents`). Passes through iTerm2 and terminal environment variables. Requires `SYS_ADMIN` capability and unconfined seccomp for bubblewrap sandboxing.
- **chrome-devtools-mcp-host** - Wrapper (installed to `/usr/local/bin`) that runs `chrome-devtools-mcp` as a stdio MCP server against a Chrome running on the *host* (started by `make chrome`). It first starts a `socat` bridge on the container's `127.0.0.1:9333` forwarding to `host.docker.internal:9333`, so the MCP connects via a loopback/IP Host header (Chrome rejects other Host headers as DNS-rebinding). Register it inside the container with `claude mcp add chrome-devtools --scope user -- chrome-devtools-mcp-host`.
- **tab_color.zsh** - iTerm2 tab color helper using `precmd_functions` hook; color is set via `IT2_TAB_COLOR` env var (defaults to red `#FF0000` inside the container via `/.envrc`).
- **com.mcfedr.agents-chrome.plist** - launchd template (bootstrapped from `/tmp`, never installed into `~/Library/LaunchAgents`) that runs `make chrome` under supervision, so the host Chrome restarts if it dies but does not survive logout.
- **Makefile** - `build`/`install`, the `chrome*` targets that run and supervise the host browser, and `docker-credhelpers`.

## Key Design Decisions

- Credentials are mounted read-only where possible; mutable state dirs (`.claude_agents`, `.codex_agents`, `.aws_agents`, `.kube_agents`, `.config/gcloud_agents`, atuin history) use separate host paths to avoid polluting the user's native tool configs.
- The container uses `--cap-add=SYS_ADMIN --security-opt seccomp=unconfined` because Claude CLI uses bubblewrap (`bwrap`) for sandboxing.
- The host Docker socket is bind-mounted and the docker CLI/compose/buildx are installed, so `docker` inside the container drives the *host* daemon (no nested daemon). Docker Desktop exposes that socket as root:root 0660, so the container is created with `--group-add 0` to let the non-root `agent` user reach it. Registry credentials go to a separate `~/.docker_agents` because the host's `credsStore: desktop` helper does not exist in the image.
- Registry auth uses credential helpers rather than stored logins: `docker-credential-ecr-login` (Alpine package) and `docker-credential-gcloud` (shipped with the gcloud SDK, symlinked onto PATH). Both resolve credentials from the per-context `~/.aws` and `~/.config/gcloud` mounts, so each context authenticates as its own account. The `docker-credhelpers` make target seeds `credHelpers` into each context's `config.json`, merging with jq so an in-container `docker login` is not clobbered.
- Browser automation runs one `chrome-devtools-mcp` per agent *inside* the container, attached to a single host Chrome via `--browser-url` and the socat bridge. Nothing in the container launches Chrome, so concurrent agents never contend for the single-writer lock on the browser profile; they are simply several CDP clients on one browser. The MCP is installed into the image rather than resolved through `npx` on each spawn, so agent startup does not wait on the npm registry.
- The MCP deliberately speaks stdio rather than sitting behind an HTTP gateway on the host: Claude Code gives HTTP servers a 60-second per-request first-byte timer and a 5-minute idle window, against no per-request timer and a 30-minute idle window for stdio. Long calls (`lighthouse_audit`, trace recording) time out over HTTP but not over stdio.
- `USE_BUILTIN_RIPGREP=0` is set so Claude CLI uses the system-installed ripgrep rather than its bundled copy.
- fnm is configured with `FNM_COREPACK_ENABLED=true` for automatic Node version management with corepack support.
