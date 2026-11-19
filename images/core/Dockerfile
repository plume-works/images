# Core image: the toolchains every other image here is built on, also used directly as a CI job container.
# The default user stays root (no USER line), because GitHub Actions job containers expect it.
FROM ubuntu:26.04@sha256:d66b366dac61b575bee2aef07e9c26e8070096fbe84a3d4d3eb0da069b5d76db

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# apt packages float within the Ubuntu release at build time (Git included);
# everything else below is pinned by version. jq is an interactive convenience (see the admission rule below).
# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git gnupg jq sudo unzip xz-utils \
 && rm -rf /var/lib/apt/lists/*

# dev: the non-root user at UID 1000, with bash and passwordless sudo.
# The base image ships user `ubuntu` at UID 1000; it is replaced, not renamed.
RUN userdel --remove ubuntu \
 && useradd --create-home --uid 1000 --user-group --shell /bin/bash dev \
 && echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev \
 && chmod 0440 /etc/sudoers.d/dev

# GitHub CLI from the release tarball: the apt repository keeps only the newest version, so it cannot be pinned.
# renovate: datasource=github-releases depName=cli/cli extractVersion=^v(?<version>.+)$
ARG GH_VERSION=2.105.0
RUN a=$(dpkg --print-architecture); f="gh_${GH_VERSION}_linux_$a.tar.gz"; d=$(mktemp -d) \
 && base="https://github.com/cli/cli/releases/download/v${GH_VERSION}" \
 && curl -fsSL "$base/$f" -o "$d/$f" \
 && sum=$(curl -fsSL "$base/gh_${GH_VERSION}_checksums.txt" | grep " $f\$" | cut -d' ' -f1) \
 && echo "${sum:?no checksum for $f}  $d/$f" | sha256sum -c - \
 && tar -xzf "$d/$f" -C "$d" \
 && install -m0755 "$d/gh_${GH_VERSION}_linux_$a/bin/gh" /usr/local/bin/gh \
 && install -d /usr/local/share/man/man1 \
 && cp "$d/gh_${GH_VERSION}_linux_$a/share/man/man1/"* /usr/local/share/man/man1/ \
 && rm -rf "$d"

# git's system-wide credential helper for GitHub is the GitHub CLI, so git authenticates wherever GH_TOKEN or
# GITHUB_TOKEN is set. The empty entry first clears any helper inherited from elsewhere for these hosts.
RUN for host in github.com gist.github.com; do \
      git config --system "credential.https://$host.helper" '' \
   && git config --system --add "credential.https://$host.helper" '!/usr/local/bin/gh auth git-credential'; \
    done

# --- Toolchains -------------------------------------------------------------------------------------------
# Everything lands in /usr/local or /opt, never under a home directory: a home volume is filled from the image
# only once, so anything installed there would freeze at that day's version and shadow newer images.
# Admission rule: a build toolchain is added only when at least two plume-works repositories need it in CI.

# Git LFS from the release tarball (apt's lags behind and floats); its filters are registered in /etc/gitconfig.
# renovate: datasource=github-releases depName=git-lfs/git-lfs extractVersion=^v(?<version>.+)$
ARG GIT_LFS_VERSION=3.8.1
RUN a=$(dpkg --print-architecture); f="git-lfs-linux-$a-v${GIT_LFS_VERSION}.tar.gz"; d=$(mktemp -d) \
 && base="https://github.com/git-lfs/git-lfs/releases/download/v${GIT_LFS_VERSION}" \
 && curl -fsSL "$base/$f" -o "$d/$f" \
 && sum=$(curl -fsSL "$base/sha256sums.asc" | grep " \*$f\$" | cut -d' ' -f1) \
 && echo "${sum:?no checksum for $f}  $d/$f" | sha256sum -c - \
 && tar -xzf "$d/$f" -C "$d" \
 && install -m0755 "$d/git-lfs-${GIT_LFS_VERSION}/git-lfs" /usr/local/bin/git-lfs \
 && git lfs install --system --skip-repo \
 && rm -rf "$d"

# uv, and the Python it manages: the interpreter under /opt/uv/python, python/python3 linked into /usr/local/bin.
# The UV_* locations are build-time only. At run time a user's own extra Pythons and tools go to their home
# (their choice, not something the image ships), while the image's Python is found through PATH.
# renovate: datasource=github-releases depName=astral-sh/uv
ARG UV_VERSION=0.13.9
RUN t="$(uname -m)-unknown-linux-gnu"; d=$(mktemp -d) \
 && u="https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-$t.tar.gz" \
 && curl -fsSL "$u" -o "$d/uv.tgz" \
 && echo "$(curl -fsSL "$u.sha256" | cut -d' ' -f1)  $d/uv.tgz" | sha256sum -c - \
 && tar -xzf "$d/uv.tgz" -C /usr/local/bin --strip-components=1 "uv-$t/uv" "uv-$t/uvx" \
 && rm -rf "$d"
# renovate: datasource=python-version depName=python
ARG PYTHON_VERSION=3.15.2
RUN UV_PYTHON_INSTALL_DIR=/opt/uv/python UV_PYTHON_BIN_DIR=/usr/local/bin UV_CACHE_DIR=/tmp/uv-cache \
    uv python install "${PYTHON_VERSION}" --default --preview-features python-install-default \
 && rm -rf /tmp/uv-cache

# Bun, which also covers the need for Node.js (deliberately absent).
# renovate: datasource=github-releases depName=oven-sh/bun extractVersion=^bun-v(?<version>.+)$
ARG BUN_VERSION=1.4.4
RUN case "$(uname -m)" in x86_64) b=x64 ;; aarch64) b=aarch64 ;; esac; d=$(mktemp -d) \
 && base="https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}" \
 && curl -fsSL "$base/bun-linux-$b.zip" -o "$d/bun-linux-$b.zip" \
 && sum=$(curl -fsSL "$base/SHASUMS256.txt" | grep " bun-linux-$b.zip\$" | cut -d' ' -f1) \
 && echo "${sum:?no checksum for bun-linux-$b.zip}  $d/bun-linux-$b.zip" | sha256sum -c - \
 && unzip -q "$d/bun-linux-$b.zip" -d "$d" \
 && install -m0755 "$d/bun-linux-$b/bun" /usr/local/bin/bun \
 && ln -s bun /usr/local/bin/bunx \
 && rm -rf "$d"

# CMake from Kitware's release tarball.
# renovate: datasource=github-releases depName=Kitware/CMake extractVersion=^v(?<version>.+)$
ARG CMAKE_VERSION=4.5.0
RUN f="cmake-${CMAKE_VERSION}-linux-$(uname -m).tar.gz"; d=$(mktemp -d) \
 && base="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}" \
 && curl -fsSL "$base/$f" -o "$d/$f" \
 && sum=$(curl -fsSL "$base/cmake-${CMAKE_VERSION}-SHA-256.txt" | grep " $f\$" | cut -d' ' -f1) \
 && echo "${sum:?no checksum for $f}  $d/$f" | sha256sum -c - \
 && tar -xzf "$d/$f" -C /usr/local --strip-components=1 --exclude='*/doc' --exclude='*/man' \
 && rm -rf "$d"

# Ninja (its releases publish no checksums).
# renovate: datasource=github-releases depName=ninja-build/ninja extractVersion=^v(?<version>.+)$
ARG NINJA_VERSION=1.13.2
RUN case "$(uname -m)" in x86_64) f=ninja-linux.zip ;; aarch64) f=ninja-linux-aarch64.zip ;; esac; d=$(mktemp -d) \
 && curl -fsSL "https://github.com/ninja-build/ninja/releases/download/v${NINJA_VERSION}/$f" -o "$d/$f" \
 && unzip -q "$d/$f" -d /usr/local/bin \
 && rm -rf "$d"

# fish, the upstream static build: Ubuntu's package would pull in a second Python. bash stays dev's shell.
# renovate: datasource=github-releases depName=fish-shell/fish-shell
ARG FISH_VERSION=4.9.3
RUN d=$(mktemp -d) \
 && curl -fsSL "https://github.com/fish-shell/fish-shell/releases/download/${FISH_VERSION}/fish-${FISH_VERSION}-linux-$(uname -m).tar.xz" -o "$d/fish.tar.xz" \
 && tar -xJf "$d/fish.tar.xz" -C /usr/local/bin fish \
 && echo /usr/local/bin/fish >> /etc/shells \
 && rm -rf "$d"

# --- Agent CLIs -------------------------------------------------------------------------------------------
# Installed bare: no settings, plugins, skills, MCP servers or credentials. Turning self-updating off is part
# of installing them, not configuration.

# Claude Code: the native binary from Anthropic's release bucket, checked against the GPG-signed manifest.
# (The official installer puts it under ~/.local, and the npm package needs Node.js.)
# renovate: datasource=npm depName=@anthropic-ai/claude-code
ARG CLAUDE_CODE_VERSION=2.1.327
RUN case "$(uname -m)" in x86_64) p=linux-x64 ;; aarch64) p=linux-arm64 ;; esac; d=$(mktemp -d) \
 && base="https://downloads.claude.ai/claude-code-releases/${CLAUDE_CODE_VERSION}" \
 && curl -fsSL "$base/manifest.json" -o "$d/manifest.json" \
 && curl -fsSL "$base/manifest.json.sig" -o "$d/manifest.json.sig" \
 && export GNUPGHOME="$d/gnupg" && mkdir -m700 "$GNUPGHOME" \
 && curl -fsSL https://downloads.claude.ai/keys/claude-code.asc | gpg -q --import \
 && gpg --with-colons --fingerprint | grep '^fpr:::::::::31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE:' >/dev/null \
 && gpg -q --verify "$d/manifest.json.sig" "$d/manifest.json" \
 && sum=$(grep -A3 "\"$p\"" "$d/manifest.json" | sed -n 's/.*"checksum": *"\([0-9a-f]\{64\}\)".*/\1/p') \
 && curl -fsSL "$base/$p/claude" -o "$d/claude" \
 && echo "${sum:?no checksum for $p}  $d/claude" | sha256sum -c - \
 && install -m0755 "$d/claude" /usr/local/bin/claude \
 && rm -rf "$d"

# OpenCode 2: the release binary (its releases are immutable but publish no checksum file).
# The 1.x line still gets releases, and GitHub marks them "latest"; Renovate offers the highest version, so it
# stays on 2.x, and the anchored extractVersion skips the repository's process-daemon-v* releases.
# renovate: datasource=github-releases depName=anomalyco/opencode extractVersion=^v(?<version>.+)$
ARG OPENCODE_VERSION=2.3.2
RUN case "$(uname -m)" in x86_64) p=linux-x64 ;; aarch64) p=linux-arm64 ;; esac; d=$(mktemp -d) \
 && curl -fsSL "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-$p.tar.gz" -o "$d/opencode.tgz" \
 && tar -xzf "$d/opencode.tgz" -C "$d" \
 && install -m0755 "$d/opencode" /usr/local/bin/opencode \
 && rm -rf "$d"

# No self-updating, system-wide, for both agents; a version changes only through a tested pull request.
# - Claude Code: the managed settings file applies to every user, cannot be overridden by a user's own
#   settings, and survives a scrubbed environment. DISABLE_UPDATES also blocks `claude update`.
# - OpenCode 2 reads only the environment and the user's own config for its update check (its system config,
#   /etc/opencode, does not reach the updater), so the variable is set for every way in: the image's ENV
#   (CI jobs, docker run/exec), /etc/environment (PAM logins: su -l, ssh) and environment.d (services under a
#   systemd user manager).
ENV DISABLE_AUTOUPDATER=1 DISABLE_UPDATES=1 OPENCODE_DISABLE_AUTOUPDATE=1
RUN install -d /etc/claude-code /etc/environment.d \
 && printf '{\n  "env": {\n    "DISABLE_AUTOUPDATER": "1",\n    "DISABLE_UPDATES": "1"\n  }\n}\n' \
      > /etc/claude-code/managed-settings.json \
 && printf '%s\n' DISABLE_AUTOUPDATER=1 DISABLE_UPDATES=1 OPENCODE_DISABLE_AUTOUPDATE=1 \
      | tee -a /etc/environment > /etc/environment.d/50-no-self-update.conf

# Docker engine, CLI, Buildx and Compose from Docker's apt repository, which keeps old versions, so they pin.
# containerd.io floats. The packages also enable docker.service and containerd.service for systemd,
# which the core systemd image relies on; here, without systemd, start-docker runs the engine on demand.
# renovate: datasource=github-releases depName=moby/moby extractVersion=^docker-v(?<version>.+)$
ARG DOCKER_VERSION=29.10.0
# renovate: datasource=github-releases depName=docker/buildx extractVersion=^v(?<version>.+)$
ARG BUILDX_VERSION=0.39.0
# renovate: datasource=github-releases depName=docker/compose extractVersion=^v(?<version>.+)$
ARG COMPOSE_VERSION=5.8.0
# hadolint ignore=DL3008
RUN install -m0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
 && . /etc/os-release \
 && echo "deb [signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
      > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      "docker-ce=5:${DOCKER_VERSION}-*" "docker-ce-cli=5:${DOCKER_VERSION}-*" \
      "docker-buildx-plugin=${BUILDX_VERSION}-*" "docker-compose-plugin=${COMPOSE_VERSION}-*" containerd.io \
 && rm -rf /var/lib/apt/lists/* \
 && usermod -aG docker dev
COPY --chmod=0755 start-docker /usr/local/bin/start-docker

# The engine's storage is declared as volumes, so the engine works without volume flags: on the container's
# own overlay filesystem it cannot start containers. /var/lib/containerd is where containerd.service keeps its
# data under systemd. Inherited by every image built on this one, and a child image's build steps cannot write
# there (ADR 0004). Declared last, so nothing in this build writes there afterwards either.
VOLUME ["/var/lib/docker", "/var/lib/containerd"]
