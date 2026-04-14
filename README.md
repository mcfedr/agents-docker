# agents-docker

A containerised development environment that bundles multiple AI coding assistants and everyday dev tools into a single Docker image. Run `agents` from any project directory to drop into an interactive shell with everything pre-configured.

## Why use this?

**One image, every tool.** Claude CLI, Gemini CLI, and OpenAI Codex are installed and ready to use alongside Node.js, Python, Go, AWS CLI, database clients, and more. No need to install or update each tool individually on your host machine.

**Isolated from your host.** The environment runs inside a container so tool versions, global packages, and shell configuration never conflict with your local setup. Upgrade or rebuild the image without touching your system.

**Your credentials, your project.** The `agents` script mounts your current working directory, SSH keys, git config, AWS credentials, and CLI auth tokens into the container automatically. Credentials are mounted read-only where possible. You work on your own files with your own accounts — nothing is copied into the image.

**Separate state per context.** AI tool state (Claude settings, Codex config, AWS credentials) is stored in dedicated host directories (`~/.claude_agents`, `~/.codex_agents`, `~/.aws_agents`) so the containerised tools don't interfere with your native installations.

**Comfortable shell.** Zsh with starship prompt, atuin history search, fnm for automatic Node version switching, direnv for per-project env vars, and iTerm2 integration including tab colouring so you can tell at a glance when you're inside the container.

## Networking

The container runs with `--net=host`, sharing the host's network stack directly. This means dev servers started inside the container (e.g. `npm run dev` on port 3000) are accessible on the host at `localhost:3000` without any port mapping, and the container can reach host-local services like databases or API servers as if it were running natively.

## Prerequisites

- Docker (with support for `--cap-add=SYS_ADMIN` and `--net=host` — needed for Claude CLI's bubblewrap sandbox and host network access)
- ARM64 host (the Atlassian CLI binary is arm64; everything else is architecture-neutral via Alpine packages)

## Getting started

```bash
# Build the image
make build

# Add the agents command to your PATH
make install

# Launch the environment from any project directory
cd ~/my-project
agents
```

This opens a zsh shell inside the container with `~/my-project` mounted at its original path. All changes you make to files are reflected on the host immediately.

## What's included

| Category | Tools |
|---|---|
| AI assistants | Claude CLI, Gemini CLI, OpenAI Codex |
| Languages & runtimes | Node.js, npm, pnpm, fnm (with corepack), Python 3, uv, Go |
| Cloud & infrastructure | AWS CLI, GitHub CLI (gh), GitLab CLI (glab), Atlassian CLI (acli) |
| Databases | MariaDB client, PostgreSQL 18 client |
| Shell & productivity | zsh, starship, atuin, direnv, tmux, ripgrep, difftastic, jq, nano |

## Customisation

- **Tab colour** — Set the `IT2_TAB_COLOR` environment variable to a hex colour code (e.g. `FF0000` for red). The container defaults to red so you can visually distinguish it from host terminal tabs.
- **Node versions** — fnm is pre-installed with corepack enabled. Add a `.node-version` or `.nvmrc` file to your project and the correct version is activated on `cd`.
- **Per-project env** — direnv is hooked into zsh. Add a `.envrc` to any project directory for automatic environment variable loading.

## Volume mounts

The `agents` script mounts these host paths into the container:

| Host path | Container path | Mode |
|---|---|---|
| Current directory | Same path | read-write (delegated) |
| `~/.claude_agents` | `~/.claude` | read-write |
| `~/.claude.json` | `~/.claude.json` | read-write |
| `~/.codex_agents` | `~/.codex` | read-write |
| `~/.aws_agents` | `~/.aws` | read-write |
| `~/.ssh` | `~/.ssh` | read-only |
| `~/.gitconfig` | `~/.gitconfig` | read-only |
| `~/.npmrc` | `~/.npmrc` | read-only |
| `~/.netrc` | `~/.netrc` | read-only |
| `~/.config/gh` | `~/.config/gh` | read-only |
| `~/.config/glab-cli` | `~/.config/glab-cli` | read-only |
| `~/.config/acli` | `~/.config/acli` | read-only |
| `~/.config/atuin` | `~/.config/atuin` | read-only |
| `~/.config/starship.toml` | `~/.config/starship.toml` | read-only |
| `~/.config/direnv` | `~/.config/direnv` | read-only |
| `~/.local/share/atuin` | `~/.local/share/atuin` | read-write |
| `~/.local/share/direnv` | `~/.local/share/direnv` | read-write |

Make sure these host paths exist before running `agents`, or remove the corresponding `-v` lines from the script for any you don't need.
