FROM alpine:3

RUN apk add --no-cache \
    aws-cli \
    aws-cli-doc \
    aws-cli-zsh-completion \
    bash \
    bubblewrap \
    curl \
    difftastic \
    direnv \
    git \
    github-cli \
    glab \
    go \
    jq \
    libgcc \
    libstdc++ \
    make \
    mariadb-client \
    nano \
    nodejs \
    npm \
    pnpm \
    postgresql18-client \
    python3 \
    ripgrep \
    tmux \
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

# Claude CLI
RUN curl -fsSL https://claude.ai/install.sh | bash \
    && mv $(readlink ~/.local/bin/claude) /usr/local/bin/claude \
    && rm ~/.local/bin/claude

ENV USE_BUILTIN_RIPGREP=0

# Gemini CLI
RUN npm install -g @google/gemini-cli

# SonarQube CLI
# no arm64 build
# RUN curl -o- https://raw.githubusercontent.com/SonarSource/sonarqube-cli/refs/heads/master/user-scripts/install.sh | bash
    # && mv ~/.local/share/sonarqube-cli/bin/sonar /usr/local/bin/sonar

# Copilot CLI
# checksum fail
# RUN curl -fsSL https://gh.io/copilot-install | bash

# Atuin CLI
RUN curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh \
    && mv ~/.atuin/bin/atuin /usr/local/bin/atuin

RUN echo 'export IT2_TAB_COLOR=FF0000' >> /.envrc

# RUN curl -LO https://github.com/openai/codex/releases/download/rust-v0.118.0/codex-aarch64-unknown-linux-musl.tar.gz \
#     && tar -xzf codex-aarch64-unknown-linux-musl.tar.gz \
#     && mv codex-aarch64-unknown-linux-musl /usr/local/bin/codex \
#     && rm codex-aarch64-unknown-linux-musl.tar.gz

# Codex
RUN npm i -g @openai/codex

ENV PRODUCT=terraform
ENV VERSION=1.14.8
RUN case "$TARGETPLATFORM" in \
        "linux/arm64") TF_PLATFORM="linux_arm64" ;; \
        "linux/amd64") TF_PLATFORM="linux_amd64" ;; \
        *) echo "Unsupported TARGETPLATFORM: $TARGETPLATFORM" && exit 1 ;; \
    esac \
    && apk add --update --virtual .deps --no-cache gnupg unzip \
    && cd /tmp \
    && wget "https://releases.hashicorp.com/${PRODUCT}/${VERSION}/${PRODUCT}_${VERSION}_${TF_PLATFORM}.zip" \
    && wget "https://releases.hashicorp.com/${PRODUCT}/${VERSION}/${PRODUCT}_${VERSION}_SHA256SUMS" \
    && wget "https://releases.hashicorp.com/${PRODUCT}/${VERSION}/${PRODUCT}_${VERSION}_SHA256SUMS.sig" \
    && wget -qO- https://www.hashicorp.com/.well-known/pgp-key.txt | gpg --import \
    && gpg --verify ${PRODUCT}_${VERSION}_SHA256SUMS.sig ${PRODUCT}_${VERSION}_SHA256SUMS \
    && grep "${PRODUCT}_${VERSION}_${TF_PLATFORM}.zip" ${PRODUCT}_${VERSION}_SHA256SUMS | sha256sum -c \
    && unzip "/tmp/${PRODUCT}_${VERSION}_${TF_PLATFORM}.zip" -d /tmp \
    && mv /tmp/${PRODUCT} /usr/local/bin/${PRODUCT} \
    && rm -f "/tmp/${PRODUCT}_${VERSION}_${TF_PLATFORM}.zip" ${PRODUCT}_${VERSION}_SHA256SUMS ${PRODUCT}_${VERSION}_SHA256SUMS.sig \
    && apk del .deps

ENV TERRAGRUNT_VERSION=v1.0.1
RUN case "$TARGETPLATFORM" in \
        "linux/arm64") TG_ARCH="arm64" ;; \
        "linux/amd64") TG_ARCH="amd64" ;; \
        *) echo "Unsupported TARGETPLATFORM: $TARGETPLATFORM" && exit 1 ;; \
    esac \
    && apk add --update --virtual .tgdeps --no-cache gnupg \
    && cd /tmp \
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
    && rm -f "${TG_ARCHIVE}" SHA256SUMS SHA256SUMS.gpgsig \
    && apk del .tgdeps

RUN addgroup -S agent && adduser -S agent -G agent -s /bin/zsh
USER agent
SHELL ["/bin/zsh", "-c"]

# as the user
ENV FNM_COREPACK_ENABLED=true
RUN curl -fsSL https://fnm.vercel.app/install | bash \
    && echo 'eval "$(fnm env --use-on-cd --shell zsh)"' >> ~/.zshrc

RUN echo 'eval "$(starship init zsh)"' >> ~/.zshrc
RUN echo 'eval "$(atuin init zsh)"' >> ~/.zshrc
RUN echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc

RUN echo 'bindkey "^[[H" beginning-of-line' >> ~/.zshrc \
    && echo 'bindkey "^[[F" end-of-line' >> ~/.zshrc

RUN echo '"autoload -Uz compinit"' >> ~/.zshrc \
    && echo '"compinit"' >> ~/.zshrc

RUN curl -L https://iterm2.com/shell_integration/zsh \
    -o ~/.iterm2_shell_integration.zsh \
    && echo 'source ~/.iterm2_shell_integration.zsh' >> ~/.zshrc

COPY tab_color.zsh /home/agent/.tab_color.zsh
RUN echo 'source ~/.tab_color.zsh' >> ~/.zshrc

RUN echo 'export AWS_PAGER=""' >> ~/.zshrc

WORKDIR /home/agent
ENTRYPOINT ["zsh", "--login"]
