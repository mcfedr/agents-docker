HOME_DIR := $(HOME)
LOCAL_BIN := $(HOME_DIR)/.local/bin

build:
	docker build -t mcfedr/agents .

install:
	mkdir -p $(HOME_DIR)/.claude_agents
	mkdir -p $(HOME_DIR)/.codex_agents
	mkdir -p $(HOME_DIR)/.aws_agents
	mkdir -p $(HOME_DIR)/.terraform_d_agents/plugin-cache
	mkdir -p $(HOME_DIR)/.ssh
	mkdir -p $(HOME_DIR)/.config/glab-cli
	mkdir -p $(HOME_DIR)/.config/gh
	mkdir -p $(HOME_DIR)/.config/acli
	mkdir -p $(HOME_DIR)/.config/atuin
	mkdir -p $(HOME_DIR)/.config/direnv
	mkdir -p $(HOME_DIR)/.local/share/atuin
	mkdir -p $(HOME_DIR)/.local/share/direnv
	mkdir -p $(LOCAL_BIN)
	touch $(HOME_DIR)/.claude.json
	touch $(HOME_DIR)/.netrc
	touch $(HOME_DIR)/.npmrc
	touch $(HOME_DIR)/.gitconfig
	touch $(HOME_DIR)/.gitconfig-ek
	touch $(HOME_DIR)/.gitignore_global
	touch $(HOME_DIR)/.config/starship.toml
	touch $(HOME_DIR)/.terraformrc
	ln -sfn $(CURDIR)/agents $(LOCAL_BIN)/agents
