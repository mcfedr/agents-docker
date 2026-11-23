HOME_DIR := $(HOME)
LOCAL_BIN := $(HOME_DIR)/.local/bin

build:
	docker build -t mcfedr/agents .

build-no-cache:
	docker build --no-cache -t mcfedr/agents .

run:
	docker run -it --rm mcfedr/agents

# Run the browser the agents drive. Only Chrome runs on the host: each agent
# starts its own chrome-devtools-mcp inside the container (via the
# chrome-devtools-mcp-host wrapper) and attaches to this one over CDP, so many
# agents share the browser without contending for the profile lock that
# chrome-devtools-mcp takes when it launches Chrome itself.
#
# Two launchd jobs (see agents-chrome): one owns CHROME_PORT and starts the
# browser on the first connection, the other runs Chrome on a private port and
# quits it after half an hour with no agent connected. The plists are
# bootstrapped from /tmp, NOT installed into ~/Library/LaunchAgents, so they do
# not auto-load: they stay gone after logout/reboot until `make chrome-start` again.
CHROME_LOG := /tmp/agents-chrome.log
CHROME_LABEL := com.mcfedr.agents-chrome
CHROME_SOCKET_LABEL := com.mcfedr.agents-chrome-socket
LAUNCHD_DOMAIN := gui/$(shell id -u)
# Not 9222: other Chromium builds (Brave in particular) claim it, and a browser
# that gets there first takes IPv4 loopback while ours silently falls back to
# [::1], which containers cannot reach through host.docker.internal.
CHROME_PORT ?= 9333

# Load both jobs (idempotent). Chrome itself only starts once an agent connects.
chrome-start:
	@set -e; \
	for label in $(CHROME_LABEL) $(CHROME_SOCKET_LABEL); do \
		if launchctl print $(LAUNCHD_DOMAIN)/$$label >/dev/null 2>&1; then \
			echo "$$label already loaded"; \
		else \
			sed -e 's|__WORKDIR__|$(CURDIR)|' -e 's|__PORT__|$(CHROME_PORT)|' $(CURDIR)/$$label.plist > /tmp/$$label.plist; \
			launchctl bootstrap $(LAUNCHD_DOMAIN) /tmp/$$label.plist; \
			echo "$$label loaded"; \
		fi; \
	done; \
	echo "logs: $(CHROME_LOG)"

# Unload both jobs, quitting Chrome if it is running.
chrome-stop:
	@for label in $(CHROME_SOCKET_LABEL) $(CHROME_LABEL); do \
		if launchctl print $(LAUNCHD_DOMAIN)/$$label >/dev/null 2>&1; then \
			launchctl bootout $(LAUNCHD_DOMAIN)/$$label && echo "$$label unloaded"; \
		else \
			echo "$$label not loaded"; \
		fi; \
	done

chrome-status:
	@if ! launchctl print $(LAUNCHD_DOMAIN)/$(CHROME_SOCKET_LABEL) >/dev/null 2>&1; then \
		echo "not loaded"; \
	elif launchctl print $(LAUNCHD_DOMAIN)/$(CHROME_LABEL) 2>/dev/null | grep -q 'state = running'; then \
		echo "listening on $(CHROME_PORT), chrome running, logs: $(CHROME_LOG)"; \
	else \
		echo "listening on $(CHROME_PORT), chrome idle, logs: $(CHROME_LOG)"; \
	fi

chrome-logs:
	@tail -f $(CHROME_LOG)

# Registry credential helpers for the containerised docker CLI. The helper
# binaries ship in the image; ecr-login reads the context's ~/.aws mount and
# docker-credential-gcloud its gcloud config, so each context authenticates as
# its own account. Merged rather than overwritten, so a `docker login` done
# inside the container survives re-running this.
GCLOUD_CREDHELPERS := "europe-west1-docker.pkg.dev":"gcloud","us-east1-docker.pkg.dev":"gcloud"
CREDHELPERS := {$(GCLOUD_CREDHELPERS)}
CREDHELPERS_SMARTSUITE := {$(GCLOUD_CREDHELPERS),"864514156870.dkr.ecr.us-east-2.amazonaws.com":"ecr-login"}
CREDHELPERS_EKREATIVE := {$(GCLOUD_CREDHELPERS),"691282246055.dkr.ecr.us-east-1.amazonaws.com":"ecr-login"}

docker-credhelpers:
	@set -e; \
	merge() { \
		mkdir -p "$$(dirname "$$1")"; \
		[ -s "$$1" ] || echo '{}' > "$$1"; \
		jq -S --argjson h "$$2" '.credHelpers = ((.credHelpers // {}) + $$h)' "$$1" > "$$1.tmp"; \
		mv "$$1.tmp" "$$1"; \
		echo "credHelpers -> $$1"; \
	}; \
	merge $(HOME_DIR)/.docker_agents/config.json '$(CREDHELPERS)'; \
	merge $(HOME_DIR)/.docker_agents_smartsuite/config.json '$(CREDHELPERS_SMARTSUITE)'; \
	merge $(HOME_DIR)/.docker_agents_ekreative/config.json '$(CREDHELPERS_EKREATIVE)'; \
	merge $(HOME_DIR)/.docker_agents_edrone/config.json '$(CREDHELPERS)'

.PHONY: build chrome-start chrome-stop chrome-status chrome-logs install docker-credhelpers

install: docker-credhelpers
	mkdir -p $(HOME_DIR)/.claude_agents
	mkdir -p $(HOME_DIR)/.claude_agents_smartsuite
	mkdir -p $(HOME_DIR)/.claude_agents_ekreative
	mkdir -p $(HOME_DIR)/.claude_agents_edrone
	mkdir -p $(HOME_DIR)/.codex_agents
	mkdir -p $(HOME_DIR)/.config/opencode_agents
	mkdir -p $(HOME_DIR)/.config/opencode_agents_smartsuite
	mkdir -p $(HOME_DIR)/.config/opencode_agents_ekreative
	mkdir -p $(HOME_DIR)/.config/opencode_agents_edrone
	mkdir -p $(HOME_DIR)/.local/share/opencode_agents
	mkdir -p $(HOME_DIR)/.local/share/opencode_agents_smartsuite
	mkdir -p $(HOME_DIR)/.local/share/opencode_agents_ekreative
	mkdir -p $(HOME_DIR)/.local/share/opencode_agents_edrone
	mkdir -p $(HOME_DIR)/.local/state/opencode_agents
	mkdir -p $(HOME_DIR)/.local/state/opencode_agents_smartsuite
	mkdir -p $(HOME_DIR)/.local/state/opencode_agents_ekreative
	mkdir -p $(HOME_DIR)/.local/state/opencode_agents_edrone
	mkdir -p $(HOME_DIR)/.aws_agents
	mkdir -p $(HOME_DIR)/.aws_agents_smartsuite
	mkdir -p $(HOME_DIR)/.aws_agents_ekreative
	mkdir -p $(HOME_DIR)/.aws_agents_edrone
	mkdir -p $(HOME_DIR)/.docker_agents
	mkdir -p $(HOME_DIR)/.docker_agents_smartsuite
	mkdir -p $(HOME_DIR)/.docker_agents_ekreative
	mkdir -p $(HOME_DIR)/.docker_agents_edrone
	mkdir -p $(HOME_DIR)/.composer_agents
	mkdir -p $(HOME_DIR)/.composer_agents_smartsuite
	mkdir -p $(HOME_DIR)/.composer_agents_ekreative
	mkdir -p $(HOME_DIR)/.composer_agents_edrone
	mkdir -p $(HOME_DIR)/.azure_agents
	mkdir -p $(HOME_DIR)/.azure_agents_smartsuite
	mkdir -p $(HOME_DIR)/.azure_agents_ekreative
	mkdir -p $(HOME_DIR)/.azure_agents_edrone
	mkdir -p $(HOME_DIR)/.config/teams-cli_agents
	mkdir -p $(HOME_DIR)/.config/teams-cli_agents_smartsuite
	mkdir -p $(HOME_DIR)/.config/teams-cli_agents_ekreative
	mkdir -p $(HOME_DIR)/.config/teams-cli_agents_edrone
	mkdir -p $(HOME_DIR)/.terraform_d_agents/plugin-cache
	mkdir -p $(HOME_DIR)/.ssh_agents
	mkdir -p $(HOME_DIR)/.ssh_agents_smartsuite
	mkdir -p $(HOME_DIR)/.ssh_agents_ekreative
	mkdir -p $(HOME_DIR)/.ssh_agents_edrone
	mkdir -p $(HOME_DIR)/.config/glab-cli_agents
	mkdir -p $(HOME_DIR)/.config/glab-cli_agents_smartsuite
	mkdir -p $(HOME_DIR)/.config/glab-cli_agents_ekreative
	mkdir -p $(HOME_DIR)/.config/glab-cli_agents_edrone
	mkdir -p $(HOME_DIR)/.config/gh_agents
	mkdir -p $(HOME_DIR)/.config/gh_agents_smartsuite
	mkdir -p $(HOME_DIR)/.config/gh_agents_ekreative
	mkdir -p $(HOME_DIR)/.config/gh_agents_edrone
	mkdir -p $(HOME_DIR)/.config/anthropic_agents
	mkdir -p $(HOME_DIR)/.config/anthropic_agents_smartsuite
	mkdir -p $(HOME_DIR)/.config/anthropic_agents_ekreative
	mkdir -p $(HOME_DIR)/.config/anthropic_agents_edrone
	mkdir -p $(HOME_DIR)/.kube_agents
	mkdir -p $(HOME_DIR)/.kube_agents_smartsuite
	mkdir -p $(HOME_DIR)/.kube_agents_ekreative
	mkdir -p $(HOME_DIR)/.kube_agents_edrone
	mkdir -p $(HOME_DIR)/.config/gcloud_agents
	mkdir -p $(HOME_DIR)/.config/gcloud_agents_smartsuite
	mkdir -p $(HOME_DIR)/.config/gcloud_agents_ekreative
	mkdir -p $(HOME_DIR)/.config/gcloud_agents_edrone
	mkdir -p $(HOME_DIR)/.config/acli
	mkdir -p $(HOME_DIR)/.config/atuin_agents
	mkdir -p $(HOME_DIR)/.config/atuin_agents_smartsuite
	mkdir -p $(HOME_DIR)/.config/atuin_agents_ekreative
	mkdir -p $(HOME_DIR)/.config/atuin_agents_edrone
	mkdir -p $(HOME_DIR)/.config/direnv
	mkdir -p $(HOME_DIR)/.local/share/atuin_agents
	mkdir -p $(HOME_DIR)/.local/share/atuin_agents_smartsuite
	mkdir -p $(HOME_DIR)/.local/share/atuin_agents_ekreative
	mkdir -p $(HOME_DIR)/.local/share/atuin_agents_edrone
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
	touch $(HOME_DIR)/.claude_agents_edrone.json
	touch $(HOME_DIR)/.netrc
	touch $(HOME_DIR)/.netrc_smartsuite
	touch $(HOME_DIR)/.netrc_ekreative
	touch $(HOME_DIR)/.netrc_edrone
	touch $(HOME_DIR)/.npmrc
	touch $(HOME_DIR)/.npmrc_smartsuite
	touch $(HOME_DIR)/.npmrc_ekreative
	touch $(HOME_DIR)/.npmrc_edrone
	touch $(HOME_DIR)/.gitconfig_agents
	touch $(HOME_DIR)/.gitconfig_agents_smartsuite
	touch $(HOME_DIR)/.gitconfig_agents_ekreative
	touch $(HOME_DIR)/.gitconfig_agents_edrone
	touch $(HOME_DIR)/.gitignore_global
	touch $(HOME_DIR)/.config/starship.toml
	touch $(HOME_DIR)/.terraformrc
	touch $(HOME_DIR)/.terraformrc_smartsuite
	touch $(HOME_DIR)/.terraformrc_ekreative
	touch $(HOME_DIR)/.terraformrc_edrone
	touch $(HOME_DIR)/.claude/CLAUDE.md
	ln -sfn $(CURDIR)/agents $(LOCAL_BIN)/agents
	launchctl setenv OLLAMA_HOST "0.0.0.0:11434"

plandesk-init:
	npm i -g @plandesk/cli
	plandesk init

plandesk:
	plandesk serve
