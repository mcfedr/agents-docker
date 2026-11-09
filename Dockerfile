FROM ubuntu:26.04

# The distro supplies the system pieces, the build toolchain and the headers that
# native extensions compile against. These stay with apt so `gdal-config`,
# `pg_config` and the headers match the shared libraries found at runtime.
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    bubblewrap \
    build-essential \
    ca-certificates \
    clang \
    clang-format \
    clang-tidy \
    clangd \
    curl \
    file \
    gdal-bin \
    gettext \
    git \
    less \
    libcairo2 \
    libcurl4-openssl-dev \
    libgdal-dev \
    libgeos-dev \
    libicu-dev \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libpangoft2-1.0-0 \
    libpq-dev \
    libproj-dev \
    libprotobuf-dev \
    openssh-client \
    pkgconf \
    procps \
    python3 \
    python3-dev \
    python3-venv \
    unzip \
    zsh \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=C.UTF-8

RUN userdel -r ubuntu \
    && useradd -m -s /usr/bin/zsh -U agent \
    && mkdir -p /home/linuxbrew/.linuxbrew \
    && chown -R agent:agent /home/linuxbrew

# The docker CLI only discovers plugins in fixed system directories (or via
# ~/.docker/config.json, which is a host mount), so point one at brew's copies.
RUN mkdir -p /usr/local/lib/docker/cli-plugins \
    && ln -s /home/linuxbrew/.linuxbrew/lib/docker/cli-plugins/docker-buildx /usr/local/lib/docker/cli-plugins/docker-buildx \
    && ln -s /home/linuxbrew/.linuxbrew/lib/docker/cli-plugins/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose

RUN echo 'export IT2_TAB_COLOR=FF0000' >> /.envrc

# Keg-only formulae and the gcloud SDK's component bin go after the system dirs,
# so apt's `pg_config` (matching libpq-dev) wins over brew libpq's.
ENV HOMEBREW_PREFIX=/home/linuxbrew/.linuxbrew \
    HOMEBREW_NO_ANALYTICS=1 \
    HOMEBREW_NO_ENV_HINTS=1 \
    PATH=/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/linuxbrew/.linuxbrew/opt/rustup/bin:/home/linuxbrew/.linuxbrew/opt/libpq/bin:/home/linuxbrew/.linuxbrew/opt/mysql-client/bin:/home/linuxbrew/.linuxbrew/share/google-cloud-sdk/bin

# Homebrew refuses to run as root. The prefix is owned by `agent`, so
# `brew install`/`brew upgrade` also work inside a running container.
USER agent
RUN git clone https://github.com/Homebrew/brew /home/linuxbrew/.linuxbrew/Homebrew \
    && mkdir -p /home/linuxbrew/.linuxbrew/bin \
    && ln -s ../Homebrew/bin/brew /home/linuxbrew/.linuxbrew/bin/brew

# A single install so brew resolves and downloads everything in one pass. Not
# cache-busted: this layer only refreshes with `make build-no-cache`.
#
# Afterwards only the requested formulae stay linked. Dependency kegs (ICU,
# libxml2, curl, Python...) would otherwise shadow apt's `icu-config`,
# `xml2-config` and `python3`, and native extensions would build against brew's
# headers while loading apt's libraries, or load brew's libraries next to apt's.
# Brew's own tools reach their dependencies through opt/ paths.
RUN --mount=type=cache,target=/home/agent/.cache/Homebrew,uid=1000,gid=1000 \
    formulae=" \
    atlassian/acli/acli \
    atuin \
    awscli \
    bun \
    chrome-devtools-mcp \
    composer \
    difftastic \
    direnv \
    docker \
    docker-buildx \
    docker-compose \
    docker-credential-helper-ecr \
    fnm \
    gemini-cli \
    gh \
    git \
    git-lfs \
    glab \
    gnupg \
    go \
    golangci-lint \
    hadolint \
    hashicorp/tap/terraform \
    imagemagick \
    jq \
    kubernetes-cli \
    libpq \
    librsvg \
    mysql-client \
    nano \
    node \
    opencode \
    pandoc \
    php \
    pnpm \
    protobuf \
    ripgrep \
    rustup \
    shellcheck \
    shfmt \
    socat \
    starship \
    terragrunt \
    tmux \
    uv \
    zsh-completions \
    " \
    && brew install $formulae \
    anthropics/tap/ant \
    claude-code \
    codex \
    gcloud-cli \
    && brew list --formula \
    | grep -vxF "$(printf '%s\n' $formulae | sed 's|.*/||')" \
    | xargs --no-run-if-empty brew unlink

RUN gcloud components install gke-gcloud-auth-plugin cloud-sql-proxy --quiet

# The working directory is bind-mounted from the host, where it is owned by the
# host user's UID (e.g. 503) rather than the container's `agent` user. Docker
# Desktop's VirtioFS backend masks this by remapping ownership to the accessing
# UID, but other file-sharing backends (gRPC-FUSE/osxfs) surface the raw host
# UID, and git then refuses with "detected dubious ownership in repository".
# Trust every directory at the system level (read regardless of the read-only
# ~/.gitconfig mount and by any UID) so git works across backends. The LFS
# filters are registered system-wide for the same reason.
RUN git config --system --add safe.directory '*' \
    && git lfs install --system

USER root

ARG TARGETPLATFORM

# No Linux formula for these. uv's managed Python lives under /opt rather than
# ~/.local/share/uv, which is a host mount at runtime.
ARG UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin UV_PYTHON_INSTALL_DIR=/opt/uv-python
RUN uv tool install --managed-python azure-cli \
    && uv tool install --managed-python aws-saml-auth \
    && uv tool install --managed-python keyring --with keyrings.codeartifact

# Tools installed from upstream "latest" are each preceded by an ADD of the
# release document, so a new release changes the layer hash and the install
# re-runs instead of serving a cached layer forever.

# OpenAI API CLI — goreleaser archives verified against the release checksums file.
ADD https://api.github.com/repos/openai/openai-cli/releases/latest /tmp/openai-cli-release.json
RUN case "$TARGETPLATFORM" in \
        "linux/arm64") OPENAI_CLI_ARCH="arm64" ;; \
        "linux/amd64") OPENAI_CLI_ARCH="amd64" ;; \
        *) echo "Unsupported TARGETPLATFORM: $TARGETPLATFORM" && exit 1 ;; \
    esac \
    && cd /tmp \
    && OPENAI_CLI_TAG="$(jq -re .tag_name /tmp/openai-cli-release.json)" \
    && OPENAI_CLI_VERSION="${OPENAI_CLI_TAG#v}" \
    && OPENAI_CLI_ARCHIVE="openai_${OPENAI_CLI_VERSION}_linux_${OPENAI_CLI_ARCH}.tar.gz" \
    && OPENAI_CLI_SUMS="openai_${OPENAI_CLI_VERSION}_checksums.txt" \
    && OPENAI_CLI_BASE_URL="https://github.com/openai/openai-cli/releases/download/${OPENAI_CLI_TAG}" \
    && curl -fsSLO "${OPENAI_CLI_BASE_URL}/${OPENAI_CLI_ARCHIVE}" \
    && curl -fsSLO "${OPENAI_CLI_BASE_URL}/${OPENAI_CLI_SUMS}" \
    && grep "  ${OPENAI_CLI_ARCHIVE}$" "${OPENAI_CLI_SUMS}" | sha256sum -c \
    && tar -xzf "${OPENAI_CLI_ARCHIVE}" -C /usr/local/bin openai \
    && mkdir -p /usr/local/share/zsh/site-functions \
    && openai @completion zsh > /usr/local/share/zsh/site-functions/_openai \
    && rm -f "${OPENAI_CLI_ARCHIVE}" "${OPENAI_CLI_SUMS}"

# Copilot CLI
# checksum fail
# RUN curl -fsSL https://gh.io/copilot-install | bash

# SonarQube CLI
ADD https://binaries.sonarsource.com/Distribution/sonarqube-cli/stable.version /tmp/sonarqube-cli-version
RUN curl -o- https://raw.githubusercontent.com/SonarSource/sonarqube-cli/refs/heads/master/user-scripts/install.sh | bash \
    && mv ~/.local/share/sonarqube-cli/bin/sonar /usr/local/bin/sonar

# chrome-devtools-mcp bridge to a Chrome running on the host (see script header).
COPY --chmod=755 chrome-devtools-mcp-host /usr/local/bin/chrome-devtools-mcp-host

USER agent
SHELL ["/bin/zsh", "-c"]

RUN echo 'eval "$(fnm env --use-on-cd --shell zsh)"' >> ~/.zshrc \
    && echo 'export FNM_COREPACK_ENABLED=true' >> ~/.zshrc

RUN echo 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"' >> ~/.zshrc

RUN echo 'eval "$(starship init zsh)"' >> ~/.zshrc
RUN echo 'eval "$(atuin init zsh)"' >> ~/.zshrc
RUN echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc

RUN echo 'bindkey "^[[H" beginning-of-line' >> ~/.zshrc \
    && echo 'bindkey "^[[F" end-of-line' >> ~/.zshrc

RUN echo 'fpath+=($HOMEBREW_PREFIX/share/zsh/site-functions $HOMEBREW_PREFIX/share/zsh-completions)' >> ~/.zshrc \
    && echo 'autoload -Uz compinit' >> ~/.zshrc \
    && echo 'compinit' >> ~/.zshrc

# gcloud ships a script to source rather than an autoloadable _name function, so
# compinit never picks it up off fpath by itself. It routes through
# bashcompinit, which needs the completion system already initialised.
RUN echo 'source $HOMEBREW_PREFIX/share/google-cloud-sdk/completion.zsh.inc' >> ~/.zshrc

# Terraform and Terragrunt ship no completion file at all — each binary answers
# the bash `complete -C` protocol itself over COMP_LINE/COMP_POINT, which is all
# their -install-autocomplete flags wire up.
RUN echo 'autoload -Uz bashcompinit && bashcompinit' >> ~/.zshrc \
    && echo 'complete -o nospace -C $HOMEBREW_PREFIX/bin/terraform terraform' >> ~/.zshrc \
    && echo 'complete -o nospace -C $HOMEBREW_PREFIX/bin/terragrunt terragrunt' >> ~/.zshrc

RUN curl -L https://iterm2.com/shell_integration/zsh \
    -o ~/.iterm2_shell_integration.zsh \
    && echo 'source ~/.iterm2_shell_integration.zsh' >> ~/.zshrc

COPY tab_color.zsh /home/agent/.tab_color.zsh
RUN echo 'source ~/.tab_color.zsh' >> ~/.zshrc

RUN echo 'export AWS_PAGER=""' >> ~/.zshrc

RUN echo 'export PATH="$HOME/.composer/vendor/bin:$PATH"' >> ~/.zshrc
RUN echo 'export PATH="$PNPM_HOME/bin:$PATH"' >> ~/.zshrc

ENV USE_BUILTIN_RIPGREP=0

WORKDIR /home/agent
ENTRYPOINT ["zsh", "--login"]
