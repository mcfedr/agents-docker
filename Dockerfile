FROM rust:alpine AS fnm-builder
RUN apk add --no-cache git
ARG FNM_REPO=https://github.com/mcfedr/fnm.git
ARG FNM_BRANCH=arch
# Bust the cache when the branch advances by baking the resolved commit into the layer.
ADD https://api.github.com/repos/mcfedr/fnm/commits/arch /tmp/fnm-commit.json
RUN git clone --depth 1 --branch "$FNM_BRANCH" "$FNM_REPO" /src
WORKDIR /src
# Cache the cargo registry and target dir across builds so only changed crates
# recompile. The target mount isn't persisted in the layer, so copy the binary out.
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/target \
    cargo build --release \
    && strip target/release/fnm \
    && cp target/release/fnm /fnm

FROM alpine:3

RUN apk add --no-cache \
    aws-cli \
    aws-cli-doc \
    aws-cli-zsh-completion \
    bash \
    bubblewrap \
    build-base \
    ca-certificates \
    clang-extra-tools \
    curl \
    curl-dev \
    difftastic \
    direnv \
    docker-cli \
    docker-cli-buildx \
    docker-cli-compose \
    docker-credential-ecr-login \
    gdal \
    gdal-dev \
    gdal-tools \
    geos-dev \
    gettext \
    git \
    github-cli \
    glab \
    gnupg \
    icu-dev \
    icu-libs \
    imagemagick \
    jq \
    kubectl \
    kubectl-zsh-completion \
    libcurl \
    libgcc \
    libpq-dev \
    libstdc++ \
    make \
    mariadb-client \
    openssh-client \
    nano \
    nodejs \
    npm \
    pandoc-cli \
    pnpm \
    postgresql18-client \
    proj-dev \
    protobuf-dev \
    python3 \
    python3-dev \
    ripgrep \
    rsvg-convert \
    rustup \
    shellcheck \
    shfmt \
    socat \
    tmux \
    unzip \
    uv \
    zsh \
    zsh-completions

RUN curl -sS https://starship.rs/install.sh | sh -s -- --yes

ARG TARGETPLATFORM

# Atlassian CLI
RUN case "$TARGETPLATFORM" in \
        "linux/arm64") ACLI_PLATFORM="linux_arm64" ;; \
        "linux/amd64") ACLI_PLATFORM="linux_amd64" ;; \
        *) echo "Unsupported TARGETPLATFORM: $TARGETPLATFORM" && exit 1 ;; \
    esac \
    && curl -LO "https://acli.atlassian.com/linux/latest/${ACLI_PLATFORM}/acli" \
    && chmod +x acli \
    && mv acli /usr/local/bin/acli

# Azure CLI — no Alpine package; installed into an isolated venv from prebuilt
# musl wheels (--only-binary avoids needing a compiler / build headers).
RUN python3 -m venv /opt/azure-cli \
    && /opt/azure-cli/bin/pip install --no-cache-dir --only-binary=:all: azure-cli \
    && ln -s /opt/azure-cli/bin/az /usr/local/bin/az

# Google Cloud CLI — no Alpine package. The bundled glibc python in the archive
# can't run on musl, so gcloud is pointed at the system interpreter instead.
ENV CLOUDSDK_PYTHON=/usr/bin/python3
RUN case "$TARGETPLATFORM" in \
        "linux/arm64") GCLOUD_ARCH="arm" ;; \
        "linux/amd64") GCLOUD_ARCH="x86_64" ;; \
        *) echo "Unsupported TARGETPLATFORM: $TARGETPLATFORM" && exit 1 ;; \
    esac \
    && curl -fsSL "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-${GCLOUD_ARCH}.tar.gz" -o /tmp/gcloud.tar.gz \
    && tar -C /opt -xzf /tmp/gcloud.tar.gz \
    && rm /tmp/gcloud.tar.gz \
    && /opt/google-cloud-sdk/install.sh --quiet --usage-reporting=false --path-update=false --command-completion=false \
    && /opt/google-cloud-sdk/bin/gcloud components install gke-gcloud-auth-plugin --quiet \
    && for b in gcloud gsutil bq gke-gcloud-auth-plugin docker-credential-gcloud; do ln -s "/opt/google-cloud-sdk/bin/$b" "/usr/local/bin/$b"; done

# Atuin CLI
RUN curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh -s -- --non-interactive \
    && mv ~/.atuin/bin/atuin /usr/local/bin/atuin

RUN echo 'export IT2_TAB_COLOR=FF0000' >> /.envrc

# Every tool below resolves its version at build time. The paired ADD pulls the
# upstream "latest" document into the layer, so a new release changes the layer
# hash and the install re-runs; without it a plain `docker build` would serve a
# cached layer forever and "latest" would only mean "latest at first build".
ADD https://api.releases.hashicorp.com/v1/releases/terraform/latest /tmp/terraform-release.json
RUN case "$TARGETPLATFORM" in \
        "linux/arm64") TF_PLATFORM="linux_arm64" ;; \
        "linux/amd64") TF_PLATFORM="linux_amd64" ;; \
        *) echo "Unsupported TARGETPLATFORM: $TARGETPLATFORM" && exit 1 ;; \
    esac \
    && cd /tmp \
    && TF_VERSION="$(jq -re .version /tmp/terraform-release.json)" \
    && TF_BASE_URL="https://releases.hashicorp.com/terraform/${TF_VERSION}" \
    && wget "${TF_BASE_URL}/terraform_${TF_VERSION}_${TF_PLATFORM}.zip" \
    && wget "${TF_BASE_URL}/terraform_${TF_VERSION}_SHA256SUMS" \
    && wget "${TF_BASE_URL}/terraform_${TF_VERSION}_SHA256SUMS.sig" \
    && wget -qO- https://www.hashicorp.com/.well-known/pgp-key.txt | gpg --import \
    && gpg --verify "terraform_${TF_VERSION}_SHA256SUMS.sig" "terraform_${TF_VERSION}_SHA256SUMS" \
    && grep "terraform_${TF_VERSION}_${TF_PLATFORM}.zip" "terraform_${TF_VERSION}_SHA256SUMS" | sha256sum -c \
    && unzip "/tmp/terraform_${TF_VERSION}_${TF_PLATFORM}.zip" -d /tmp \
    && mv /tmp/terraform /usr/local/bin/terraform \
    && rm -f "terraform_${TF_VERSION}_"*

ADD https://api.github.com/repos/gruntwork-io/terragrunt/releases/latest /tmp/terragrunt-release.json
RUN case "$TARGETPLATFORM" in \
        "linux/arm64") TG_ARCH="arm64" ;; \
        "linux/amd64") TG_ARCH="amd64" ;; \
        *) echo "Unsupported TARGETPLATFORM: $TARGETPLATFORM" && exit 1 ;; \
    esac \
    && cd /tmp \
    && TERRAGRUNT_VERSION="$(jq -re .tag_name /tmp/terragrunt-release.json)" \
    && TG_ARCHIVE="terragrunt_linux_${TG_ARCH}.tar.gz" \
    && TG_BINARY="terragrunt_linux_${TG_ARCH}" \
    && TG_BASE_URL="https://github.com/gruntwork-io/terragrunt/releases/download/${TERRAGRUNT_VERSION}" \
    && curl -fsSLO "${TG_BASE_URL}/${TG_ARCHIVE}" \
    && curl -fsSLO "${TG_BASE_URL}/SHA256SUMS" \
    && curl -fsSLO "${TG_BASE_URL}/SHA256SUMS.gpgsig" \
    && curl -fsSL https://gruntwork.io/.well-known/pgp-key.txt | gpg --import \
    && gpg --verify SHA256SUMS.gpgsig SHA256SUMS \
    && grep "  ${TG_ARCHIVE}$" SHA256SUMS | sha256sum -c \
    && tar -xzf "${TG_ARCHIVE}" \
    && chmod +x "/tmp/${TG_BINARY}" \
    && mv "/tmp/${TG_BINARY}" /usr/local/bin/terragrunt \
    && rm -f "${TG_ARCHIVE}" SHA256SUMS SHA256SUMS.gpgsig

ADD https://api.github.com/repos/golangci/golangci-lint/releases/latest /tmp/golangci-lint-release.json
RUN curl -sSfL https://golangci-lint.run/install.sh | sh -s

# hadolint (Dockerfile linter) — not packaged in the Alpine repos
ADD https://api.github.com/repos/hadolint/hadolint/releases/latest /tmp/hadolint-release.json
RUN case "$TARGETPLATFORM" in \
        "linux/arm64") HADOLINT_ARCH="arm64" ;; \
        "linux/amd64") HADOLINT_ARCH="x86_64" ;; \
        *) echo "Unsupported TARGETPLATFORM: $TARGETPLATFORM" && exit 1 ;; \
    esac \
    && cd /tmp \
    && HADOLINT_VERSION="$(jq -re .tag_name /tmp/hadolint-release.json)" \
    && HADOLINT_BASE_URL="https://github.com/hadolint/hadolint/releases/download/${HADOLINT_VERSION}" \
    && curl -fsSLO "${HADOLINT_BASE_URL}/hadolint-linux-${HADOLINT_ARCH}" \
    && curl -fsSLO "${HADOLINT_BASE_URL}/checksums.sha256" \
    && grep "hadolint-linux-${HADOLINT_ARCH}$" checksums.sha256 | sha256sum -c \
    && chmod +x "hadolint-linux-${HADOLINT_ARCH}" \
    && mv "hadolint-linux-${HADOLINT_ARCH}" /usr/local/bin/hadolint \
    && rm -f checksums.sha256

ADD https://go.dev/VERSION?m=text /tmp/go-version
RUN apk add --no-cache curl tar ca-certificates \
    && case "$TARGETPLATFORM" in \
        "linux/arm64") GO_ARCH="arm64" ;; \
        "linux/amd64") GO_ARCH="amd64" ;; \
        *) echo "Unsupported TARGETPLATFORM: $TARGETPLATFORM" && exit 1 ;; \
    esac \
    && GO_VERSION="$(sed -n '1s/^go//p' /tmp/go-version)" \
    && curl -L "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" -o /tmp/go.tar.gz \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && rm /tmp/go.tar.gz

# OpenCode
ADD https://registry.npmjs.org/opencode-ai/latest /tmp/opencode-ai-latest.json
RUN npm install -g opencode-ai

# Claude CLI
ADD https://registry.npmjs.org/@anthropic-ai/claude-code/latest /tmp/claude-code-latest.json
RUN npm install -g @anthropic-ai/claude-code
ENV USE_BUILTIN_RIPGREP=0

# Gemini CLI
ADD https://registry.npmjs.org/@google/gemini-cli/latest /tmp/gemini-cli-latest.json
RUN npm install -g @google/gemini-cli
# RUN curl -fsSL https://antigravity.google/cli/install.sh | bash

# Codex
ADD https://registry.npmjs.org/@openai/codex/latest /tmp/codex-latest.json
RUN npm i -g @openai/codex

# Copilot CLI
# checksum fail
# RUN curl -fsSL https://gh.io/copilot-install | bash

# SonarQube CLI
RUN curl -o- https://raw.githubusercontent.com/SonarSource/sonarqube-cli/refs/heads/master/user-scripts/install.sh | bash \
    && mv ~/.local/share/sonarqube-cli/bin/sonar /usr/local/bin/sonar

# Bun
RUN curl -fsSL https://bun.com/install | bash \
  && mv ~/.bun/bin/bun /usr/local/bin/bun

# chrome-devtools-mcp bridge to a Chrome running on the host (see script header)
COPY chrome-devtools-mcp-host /usr/local/bin/chrome-devtools-mcp-host
RUN chmod +x /usr/local/bin/chrome-devtools-mcp-host

# The working directory is bind-mounted from the host, where it is owned by the
# host user's UID (e.g. 503) rather than the container's `agent` user (UID 100).
# Docker Desktop's VirtioFS backend masks this by remapping ownership to the
# accessing UID, but other file-sharing backends (gRPC-FUSE/osxfs) surface the
# raw host UID, and git then refuses with "detected dubious ownership in
# repository". Trust every directory at the system level (read regardless of the
# read-only ~/.gitconfig mount and by any UID) so git works across backends.
RUN git config --system --add safe.directory '*'

RUN addgroup -S agent && adduser -S agent -G agent -s /bin/zsh
USER agent
SHELL ["/bin/zsh", "-c"]

# fnm — custom build from https://github.com/Schniz/fnm/pull/1562
# adds FNM_ARCH=arm64-musl support for Alpine
COPY --from=fnm-builder /fnm /usr/local/bin/fnm
RUN echo 'eval "$(fnm env --use-on-cd --shell zsh)"' >> ~/.zshrc

RUN echo 'export FNM_COREPACK_ENABLED=true' >> ~/.zshrc \
    && echo 'export FNM_NODE_DIST_MIRROR=https://unofficial-builds.nodejs.org/download/release/' >> ~/.zshrc

RUN case "$TARGETPLATFORM" in \
        "linux/arm64") echo 'export FNM_ARCH=arm64-musl' >> ~/.zshrc ;; \
        "linux/amd64") echo 'export FNM_ARCH=x64-musl' >> ~/.zshrc ;; \
        *) echo "Unsupported TARGETPLATFORM: $TARGETPLATFORM" && exit 1 ;; \
    esac

RUN echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.zshrc

RUN echo 'eval "$(starship init zsh)"' >> ~/.zshrc
RUN echo 'eval "$(atuin init zsh)"' >> ~/.zshrc
RUN echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc

RUN echo 'bindkey "^[[H" beginning-of-line' >> ~/.zshrc \
    && echo 'bindkey "^[[F" end-of-line' >> ~/.zshrc

RUN echo 'autoload -Uz compinit' >> ~/.zshrc \
    && echo 'compinit' >> ~/.zshrc

# Both ship as scripts to source rather than autoloadable _name functions, so
# compinit never picks them up off fpath by itself. They also route bash-style
# completers through bashcompinit, which needs the completion system already
# initialised — hence after the compinit above.
RUN echo 'source /opt/google-cloud-sdk/completion.zsh.inc' >> ~/.zshrc \
    && echo 'source /usr/share/zsh/site-functions/aws_zsh_completer.sh' >> ~/.zshrc

# Terraform and Terragrunt ship no completion file at all — each binary answers
# the bash `complete -C` protocol itself over COMP_LINE/COMP_POINT, which is all
# their -install-autocomplete flags wire up. bashcompinit is repeated here (the
# completers above also load it) so the block stands on its own.
RUN echo 'autoload -Uz bashcompinit && bashcompinit' >> ~/.zshrc \
    && echo 'complete -o nospace -C /usr/local/bin/terraform terraform' >> ~/.zshrc \
    && echo 'complete -o nospace -C /usr/local/bin/terragrunt terragrunt' >> ~/.zshrc

RUN curl -L https://iterm2.com/shell_integration/zsh \
    -o ~/.iterm2_shell_integration.zsh \
    && echo 'source ~/.iterm2_shell_integration.zsh' >> ~/.zshrc

COPY tab_color.zsh /home/agent/.tab_color.zsh
RUN echo 'source ~/.tab_color.zsh' >> ~/.zshrc

RUN echo 'export AWS_PAGER=""' >> ~/.zshrc

RUN echo 'export PATH="/usr/local/go/bin:$PATH"' >> ~/.zshrc
RUN echo 'export PATH="$PNPM_HOME/bin:$PATH"' >> ~/.zshrc
RUN echo 'export USE_BUILTIN_RIPGREP=0' >> ~/.zshrc

WORKDIR /home/agent
ENTRYPOINT ["zsh", "--login"]
