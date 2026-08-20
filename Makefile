HOME_DIR := $(HOME)
LOCAL_BIN := $(HOME_DIR)/.local/bin

build:
	docker build -t mcfedr/agents .

build-no-cache:
	docker build --no-cache -t mcfedr/agents .

run:
	docker run -it --rm mcfedr/agents

# One-time host setup for `make chrome`. Installs the MCP server and gateway as
# stable global binaries so the child isn't re-resolved through npx on spawn.
chrome-install:
	npm install -g chrome-devtools-mcp supergateway

# Run chrome-devtools-mcp on the host (it launches & drives the browser itself)
# and expose it over streamable HTTP so the containerised agents can connect via
# http://host.docker.internal:8222/mcp
#
# --stateful keeps ONE persistent child process and browser across requests.
# Without it supergateway defaults to stateless, spawning a fresh browser per
# request (state is lost between tool calls, and concurrent spawns race).
#
# No --isolated: chrome-devtools-mcp then uses its default persistent profile
# (~/.cache/chrome-devtools-mcp/chrome-profile), so logins/cookies survive
# restarts. Add --user-data-dir only to override that location.
# Managed as a launchd agent for crash-restart (KeepAlive) supervision while
# logged in. The plist is bootstrapped from the repo, NOT installed into
# ~/Library/LaunchAgents, so it does not auto-load — it stays gone after
# logout/reboot until you run `make chrome` again.
CHROME_LOG := /tmp/agents-chrome.log
CHROME_LABEL := com.mcfedr.agents-chrome
CHROME_PLIST_TMPL := $(CURDIR)/com.mcfedr.agents-chrome.plist
CHROME_PLIST := /tmp/agents-chrome.plist
LAUNCHD_DOMAIN := gui/$(shell id -u)

# Run in the foreground (no launchd). This is the single source of truth for the
# gateway command; `chrome-start` runs the very same target under launchd.
chrome:
	supergateway --stdio "chrome-devtools-mcp" --outputTransport streamableHttp --stateful --sessionTimeout 600000 --port 8222

# Start the gateway under launchd in the background (idempotent). Bakes the repo
# path into a /tmp copy of the plist template, which then runs `make chrome`.
chrome-start:
	@if launchctl print $(LAUNCHD_DOMAIN)/$(CHROME_LABEL) >/dev/null 2>&1; then \
		echo "chrome gateway already running ($(CHROME_LABEL))"; \
	else \
		sed 's|__WORKDIR__|$(CURDIR)|' $(CHROME_PLIST_TMPL) > $(CHROME_PLIST) && \
		launchctl bootstrap $(LAUNCHD_DOMAIN) $(CHROME_PLIST) && \
		echo "chrome gateway started ($(CHROME_LABEL)), logs: $(CHROME_LOG)"; \
	fi

# Stop and unload the backgrounded gateway.
chrome-stop:
	@if launchctl print $(LAUNCHD_DOMAIN)/$(CHROME_LABEL) >/dev/null 2>&1; then \
		launchctl bootout $(LAUNCHD_DOMAIN)/$(CHROME_LABEL) && \
		echo "chrome gateway stopped ($(CHROME_LABEL))"; \
	else \
		echo "chrome gateway not running"; \
	fi

# Show status of the launchd agent.
chrome-status:
	@if launchctl print $(LAUNCHD_DOMAIN)/$(CHROME_LABEL) >/dev/null 2>&1; then \
		echo "running ($(CHROME_LABEL)), logs: $(CHROME_LOG)"; \
	else \
		echo "not running"; \
	fi

chrome-logs:
	@tail -f $(CHROME_LOG)

.PHONY: build chrome-install chrome chrome-start chrome-stop chrome-status chrome-logs install

install:
	mkdir -p $(HOME_DIR)/.claude_agents
	mkdir -p $(HOME_DIR)/.claude_agents_smartsuite
	mkdir -p $(HOME_DIR)/.claude_agents_ekreative
	mkdir -p $(HOME_DIR)/.codex_agents
	mkdir -p $(HOME_DIR)/.config/opencode_agents
	mkdir -p $(HOME_DIR)/.config/opencode_agents_smartsuite
	mkdir -p $(HOME_DIR)/.config/opencode_agents_ekreative
	mkdir -p $(HOME_DIR)/.local/share/opencode_agents
	mkdir -p $(HOME_DIR)/.local/share/opencode_agents_smartsuite
	mkdir -p $(HOME_DIR)/.local/share/opencode_agents_ekreative
	mkdir -p $(HOME_DIR)/.local/state/opencode_agents
	mkdir -p $(HOME_DIR)/.local/state/opencode_agents_smartsuite
	mkdir -p $(HOME_DIR)/.local/state/opencode_agents_ekreative
	mkdir -p $(HOME_DIR)/.aws_agents
	mkdir -p $(HOME_DIR)/.terraform_d_agents/plugin-cache
	mkdir -p $(HOME_DIR)/.ssh_agents
	mkdir -p $(HOME_DIR)/.config/glab-cli_agents
	mkdir -p $(HOME_DIR)/.config/glab-cli_agents_smartsuite
	mkdir -p $(HOME_DIR)/.config/glab-cli_agents_ekreative
	mkdir -p $(HOME_DIR)/.config/gh_agents
	mkdir -p $(HOME_DIR)/.config/gh_agents_smartsuite
	mkdir -p $(HOME_DIR)/.config/gh_agents_ekreative
	mkdir -p $(HOME_DIR)/.config/acli
	mkdir -p $(HOME_DIR)/.config/atuin
	mkdir -p $(HOME_DIR)/.config/direnv
	mkdir -p $(HOME_DIR)/.local/share/atuin
	mkdir -p $(HOME_DIR)/.local/share/direnv
	mkdir -p $(HOME_DIR)/.local/share/uv_agents
	mkdir -p $(HOME_DIR)/.pnpm_agents
	mkdir -p $(HOME_DIR)/.local/share/fnm_agents
	mkdir -p $(HOME_DIR)/.local/state/fnm_multishells_agents
	mkdir -p $(HOME_DIR)/.sonar_agents
	mkdir -p $(HOME_DIR)/.rustup_agents
	mkdir -p $(HOME_DIR)/.cargo_agents/bin
	mkdir -p $(LOCAL_BIN)
	touch $(HOME_DIR)/.claude_agents.json
	touch $(HOME_DIR)/.claude_agents_smartsuite.json
	touch $(HOME_DIR)/.claude_agents_ekreative.json
	touch $(HOME_DIR)/.netrc
	touch $(HOME_DIR)/.netrc_smartsuite
	touch $(HOME_DIR)/.netrc_ekreative
	touch $(HOME_DIR)/.npmrc
	touch $(HOME_DIR)/.npmrc_smartsuite
	touch $(HOME_DIR)/.npmrc_ekreative
	touch $(HOME_DIR)/.gitconfig
	touch $(HOME_DIR)/.gitconfig-ek
	touch $(HOME_DIR)/.gitconfig-ss
	touch $(HOME_DIR)/.gitignore_global
	touch $(HOME_DIR)/.config/starship.toml
	touch $(HOME_DIR)/.terraformrc
	touch $(HOME_DIR)/.terraformrc_smartsuite
	touch $(HOME_DIR)/.terraformrc_ekreative
	touch $(HOME_DIR)/.claude/CLAUDE.md
	ln -sfn $(CURDIR)/agents $(LOCAL_BIN)/agents
	launchctl setenv OLLAMA_HOST "0.0.0.0:11434"
