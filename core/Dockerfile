FROM ubuntu:26.04@sha256:6a06111c3b0a8600feadb270aec771dc239bf407b25625f93f44ab00e11f4d3c

ARG DEBIAN_FRONTEND=noninteractive

# Ubuntu apt packages. procps supplies pgrep for core/test.sh.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg sudo git git-lfs build-essential jq ripgrep less fish procps \
 && rm -rf /var/lib/apt/lists/*

# GitHub CLI from its vendor apt repository.
RUN install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && chmod a+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# Docker engine, CLI, Buildx and Compose from Docker's apt repository.
RUN install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
 && chmod a+r /etc/apt/keyrings/docker.asc \
 && . /etc/os-release \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
      > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
 && rm -rf /var/lib/apt/lists/*

# uv from its GitHub release (immutable releases), checked against the release's .sha256.
# renovate: datasource=github-releases depName=astral-sh/uv
ARG UV_VERSION=0.13.8
RUN target="$(uname -m)-unknown-linux-gnu" \
 && url="https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${target}.tar.gz" \
 && tmp="$(mktemp -d)" \
 && curl -fsSL "$url" -o "$tmp/uv.tar.gz" \
 && echo "$(curl -fsSL "$url.sha256" | cut -d' ' -f1)  $tmp/uv.tar.gz" | sha256sum -c - \
 && tar -xzf "$tmp/uv.tar.gz" -C /usr/local/bin --strip-components=1 "uv-${target}/uv" "uv-${target}/uvx" \
 && rm -rf "$tmp"

COPY --from=oven/bun:1.4.4@sha256:1d22548f177f4ff38e0c15baa3c2c46c6c2060ba2d1bc573bb4720b407548f1d /usr/local/bin/bun /usr/local/bin/bun
RUN ln -s /usr/local/bin/bun /usr/local/bin/bunx

# renovate: datasource=npm depName=@anthropic-ai/claude-code
ARG CLAUDE_CODE_VERSION=2.1.326
RUN export BUN_INSTALL_BIN=/usr/local/bin \
           BUN_INSTALL_GLOBAL_DIR=/usr/local/share/bun-global \
           BUN_INSTALL_CACHE_DIR="$(mktemp -d)" \
 && bun install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
 && rm -rf "$BUN_INSTALL_CACHE_DIR"

# renovate: datasource=npm depName=opencode-ai
ARG OPENCODE_VERSION=1.19.6
RUN export BUN_INSTALL_BIN=/usr/local/bin \
           BUN_INSTALL_GLOBAL_DIR=/usr/local/share/bun-global \
           BUN_INSTALL_CACHE_DIR="$(mktemp -d)" \
 && bun install -g "opencode-ai@${OPENCODE_VERSION}" \
 && rm -rf "$BUN_INSTALL_CACHE_DIR"

# The base image ships user `ubuntu` at uid/gid 1000; rename it to `dev`.
RUN usermod -l dev -d /home/dev -m ubuntu \
 && groupmod -n dev ubuntu \
 && usermod -s /usr/bin/fish -aG docker dev \
 && echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev \
 && chmod 0440 /etc/sudoers.d/dev

COPY --chmod=0755 start-dockerd /usr/local/bin/start-dockerd

# Keep a nested daemon's data off the container's overlay filesystem.
VOLUME /var/lib/docker

USER dev
WORKDIR /home/dev

# Where `uv tool install` and `bun add -g` put a user's own tools.
ENV PATH=/home/dev/.local/bin:/home/dev/.bun/bin:$PATH
