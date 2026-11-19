FROM ubuntu:26.04@sha256:d66b366dac61b575bee2aef07e9c26e8070096fbe84a3d4d3eb0da069b5d76db

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg sudo git git-lfs build-essential jq ripgrep less fish procps cmake ninja-build python3 \
 && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli.gpg \
 && chmod a+r /etc/apt/keyrings/githubcli.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# Docker Engine, CLI, buildx, compose
RUN install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
 && chmod a+r /etc/apt/keyrings/docker.asc \
 && . /etc/os-release \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
 && rm -rf /var/lib/apt/lists/*

# renovate: datasource=github-releases depName=astral-sh/uv
ARG UV_VERSION=0.13.8
ARG UV_SHA256_AMD64=5acfd9177cfecf0bf87578f059728215ccc884388988f55f7a65041b57387d91
ARG UV_SHA256_ARM64=74f2f5c6024d397481db228db8fc25eed420db192243f88438c118e7e013e585
ARG TARGETARCH
RUN case "${TARGETARCH}" in \
      amd64) asset=uv-x86_64-unknown-linux-gnu; sha256="${UV_SHA256_AMD64}" ;; \
      arm64) asset=uv-aarch64-unknown-linux-gnu; sha256="${UV_SHA256_ARM64}" ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
 && curl -fsSL "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/${asset}.tar.gz" -o /tmp/uv.tar.gz \
 && echo "${sha256}  /tmp/uv.tar.gz" | sha256sum -c - \
 && tar -xzf /tmp/uv.tar.gz -C /usr/local/bin --strip-components=1 "${asset}/uv" "${asset}/uvx" \
 && rm /tmp/uv.tar.gz

COPY --from=oven/bun:1.4.4@sha256:1d22548f177f4ff38e0c15baa3c2c46c6c2060ba2d1bc573bb4720b407548f1d /usr/local/bin/bun /usr/local/bin/bun
RUN ln -s bun /usr/local/bin/bunx

# renovate: datasource=npm depName=@anthropic-ai/claude-code
ARG CLAUDE_CODE_VERSION=2.1.326
RUN BUN_INSTALL_BIN=/usr/local/bin \
    BUN_INSTALL_GLOBAL_DIR=/usr/local/share/bun-global \
    BUN_INSTALL_CACHE_DIR=/tmp/bun-cache \
    bun install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} \
 && rm -rf /tmp/bun-cache

# renovate: datasource=github-releases depName=anomalyco/opencode extractVersion=^v(?<version>.+)$
ARG OPENCODE_VERSION=2.2.7
ARG OPENCODE_SHA256_AMD64=89a6cee227b54bc011179c528a5e63176032462b1a5e21723b616801cddc2ca7
ARG OPENCODE_SHA256_ARM64=c1682057f0815cb2abdd6e00305f1146ebaf1c167f0335cdb74ddc80008120e7
RUN case "${TARGETARCH}" in \
      amd64) asset=opencode-linux-x64; sha256="${OPENCODE_SHA256_AMD64}" ;; \
      arm64) asset=opencode-linux-arm64; sha256="${OPENCODE_SHA256_ARM64}" ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
 && curl -fsSL "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/${asset}.tar.gz" -o /tmp/opencode.tar.gz \
 && echo "${sha256}  /tmp/opencode.tar.gz" | sha256sum -c - \
 && tar -xzf /tmp/opencode.tar.gz -C /usr/local/bin opencode \
 && rm /tmp/opencode.tar.gz

# The base image ships uid/gid 1000 as "ubuntu"; replace it with dev.
RUN userdel --remove ubuntu \
 && useradd --create-home --uid 1000 --user-group --shell /bin/bash dev \
 && usermod -aG docker dev \
 && echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev \
 && chmod 0440 /etc/sudoers.d/dev

COPY --chmod=0755 start-docker /usr/local/bin/start-docker
VOLUME /var/lib/docker

# Nothing self-updates. The variables reach shells by three routes: the image's environment (a CI job container),
# /etc/environment (PAM logins), and Claude Code's managed settings (even an empty environment).
ENV DISABLE_AUTOUPDATER=1 DISABLE_UPDATES=1 OPENCODE_DISABLE_AUTOUPDATE=1
RUN printf '%s\n' DISABLE_AUTOUPDATER=1 DISABLE_UPDATES=1 OPENCODE_DISABLE_AUTOUPDATE=1 >> /etc/environment \
 && install -d /etc/claude-code \
 && echo '{"env": {"DISABLE_AUTOUPDATER": "1", "DISABLE_UPDATES": "1"}}' > /etc/claude-code/managed-settings.json

# git gets GitHub credentials from GH_TOKEN or GITHUB_TOKEN, through gh. The empty value resets any inherited helper.
RUN for host in github.com gist.github.com; do \
      git config --system "credential.https://${host}.helper" '' \
   && git config --system --add "credential.https://${host}.helper" '!/usr/bin/gh auth git-credential' \
   || exit 1; \
    done
