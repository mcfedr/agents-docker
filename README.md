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

## Docker

The host's Docker socket is mounted into the container and the docker CLI (plus
`compose` and `buildx`) is installed, so `docker` inside the container drives the
**host** daemon. There is no nested daemon: images you build are host images,
`docker ps` lists the host's containers — including the `agents` container you
are typing in.

Because the working directory is mounted at *the same path* it has on the host,
bind mounts and build contexts resolve correctly — `docker run -v $(pwd):/app`
and `docker compose up` in a mounted project both work, since the daemon sees
the same path. Anything **outside** the mounted directory (e.g. `~/somewhere-else`)
is not visible in the container and will not mount as you expect.

Registry credentials live in `~/.docker_agents` rather than your host `~/.docker`,
so a `docker login` inside the container does not touch your host config. The
host's `credsStore: desktop` helper does not exist in the container, which is why
the config is kept separate.

`make install` seeds each context's `config.json` with credential helpers, so ECR
and Artifact Registry pulls work without an explicit `docker login`:

| Registry | Helper | Context |
|---|---|---|
| `864514156870.dkr.ecr.us-east-2.amazonaws.com` | `ecr-login` | smartsuite |
| `691282246055.dkr.ecr.us-east-1.amazonaws.com` | `ecr-login` | ekreative |
| `europe-west1-docker.pkg.dev`, `us-east1-docker.pkg.dev` | `gcloud` | all |

Each helper reads the *same per-context state the rest of the tooling uses* —
`ecr-login` picks up the context's `~/.aws` mount and `docker-credential-gcloud`
its `~/.config/gcloud` mount — so the smartsuite context authenticates to ECR as
the smartsuite account without any extra configuration. Whatever makes `aws` and
`gcloud` work in that shell makes the registry pull work too.

The `docker-credhelpers` target merges into any existing `config.json` rather than
replacing it, so a `docker login` you did inside the container survives a re-run.
It only ever adds entries — removing a registry means editing the file by hand.

> **Security:** access to the Docker socket is equivalent to root on the host.
> The AI assistants running in this container can start privileged containers and
> mount any host path. Drop the `-v /var/run/docker.sock` line from the `agents`
> script if you don't want that.

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
| Cloud & infrastructure | AWS CLI, Azure CLI (az), Google Cloud CLI (gcloud, gsutil, bq), GitHub CLI (gh), GitLab CLI (glab), Atlassian CLI (acli) |
| Containers | docker CLI, docker compose, docker buildx (all driving the **host** daemon), docker-credential-ecr-login |
| Kubernetes | kubectl, gke-gcloud-auth-plugin |
| Databases | MariaDB client, PostgreSQL 18 client, libpq headers |
| Geospatial | GDAL 3.13 + gdal-tools (`gdalinfo`, `ogr2ogr`), GEOS, PROJ, and their headers |
| Linters & formatters | hadolint, shellcheck, shfmt, golangci-lint |
| Shell & productivity | zsh, starship, atuin, direnv, tmux, ripgrep, difftastic, jq, nano |

## Python native extensions

Alpine is musl-based, and many scientific/database Python packages publish only
glibc (`manylinux`) wheels — so pip builds them from source in your venv. The
image carries the headers those builds need, so a plain `uv venv` works without
`--system-site-packages`.

GDAL has no musl wheel and its Python bindings must match the system library
exactly, so pin the version:

```bash
uv venv && source .venv/bin/activate
uv pip install "gdal==$(gdal-config --version)"    # ~30s, compiles against system GDAL
```

`rasterio`, `fiona` and `geopandas` are likewise source builds against the same
headers. `shapely`, `pyproj`, `psycopg2-binary`, `psycopg[binary]` and `asyncpg`
ship musl wheels and install instantly. `psycopg2`, `psycopg[c]` and `pymongo`
build from source against the bundled headers.

**Known gap:** pymongo's `zstd` wire compression is unavailable. Alpine's
python3 ships the `compression.zstd` wrapper without the `_zstd` C extension,
and `backports.zstd` refuses to install on Python 3.14 by design. Use `zlib` or
`snappy` compression instead — both work.

## Browser automation with Chrome DevTools MCP

The [`chrome-devtools-mcp`](https://github.com/ChromeDevTools/chrome-devtools-mcp) server lets the AI assistants drive a real browser — navigate pages, inspect the DOM, read console and network logs, run Lighthouse, and take screenshots.

The browser has to run on the **host** (it needs a real browser binary and a display, which the container doesn't have), so the MCP server runs on the host too and the containerised assistant connects to it over the network. The MCP launches and manages its own browser instance, so there's nothing to start by hand.

**1. Install the host tools once:**

```bash
make chrome-install
```

This installs `chrome-devtools-mcp` and [`supergateway`](https://github.com/supercorp-ai/supergateway) globally, so the browser process is launched from a stable binary rather than re-resolved through `npx` on each spawn.

**2. Start the server on the host** (leave it running in a terminal):

```bash
make chrome
```

This runs `chrome-devtools-mcp` behind `supergateway` in **stateful** mode, exposing it over streamable HTTP at `http://host.docker.internal:8222/mcp`. Stateful mode is essential: it keeps a single persistent browser process across requests. (Supergateway's default is stateless — it spawns a fresh browser for every request, so page state is lost between tool calls and concurrent spawns race.) Because `--isolated` is *not* passed, `chrome-devtools-mcp` uses its default persistent profile at `~/.cache/chrome-devtools-mcp/chrome-profile`, so logins and cookies survive restarts — log into a site once and it stays logged in. To drive Brave (or another Chromium build) instead of Chrome, append `--executable-path "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"` to the `--stdio` command in the `chrome` target.

**3. Register it with Claude inside the container** (once — this persists in `~/.claude_agents.json`):

```bash
claude mcp add --transport http chrome-devtools http://host.docker.internal:8222/mcp
```

Restart `claude` and the `chrome-devtools` tools become available; the browser opens on the host on first use.

> **Security:** the SSE port exposes full control of the launched browser to anything that can reach it. Keep port `8222` firewalled to your machine, and prefer the `--isolated` profile (no logged-in sessions) as configured.

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
| `~/.docker_agents` | `~/.docker` | read-write |
| `/var/run/docker.sock` | `/var/run/docker.sock` | read-write |
| `~/.ssh` | `~/.ssh` | read-only |
| `~/.gitconfig` | `~/.gitconfig` | read-only |
| `~/.npmrc` | `~/.npmrc` | read-only |
| `~/.netrc` | `~/.netrc` | read-only |
| `~/.config/gh` | `~/.config/gh` | read-only |
| `~/.config/glab-cli` | `~/.config/glab-cli` | read-only |
| `~/.kube_agents` | `~/.kube` | read-write |
| `~/.config/gcloud_agents` | `~/.config/gcloud` | read-write |
| `~/.config/acli` | `~/.config/acli` | read-only |
| `~/.config/atuin` | `~/.config/atuin` | read-only |
| `~/.config/starship.toml` | `~/.config/starship.toml` | read-only |
| `~/.config/direnv` | `~/.config/direnv` | read-only |
| `~/.local/share/atuin` | `~/.local/share/atuin` | read-write |
| `~/.local/share/direnv` | `~/.local/share/direnv` | read-write |

Several of these are per-context: the `agents` script picks a `_smartsuite` or `_ekreative` suffixed variant (e.g. `~/.aws_agents_smartsuite`, `~/.kube_agents_ekreative`) based on the working directory, falling back to the unsuffixed path shown above. `make install` creates every variant.

Make sure these host paths exist before running `agents`, or remove the corresponding `-v` lines from the script for any you don't need.
