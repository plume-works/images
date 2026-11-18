# Core image: the toolchains every other image here is built on, also used directly as a CI job container.
# The default user stays root (no USER line), because GitHub Actions job containers expect it.
FROM ubuntu:26.04@sha256:d66b366dac61b575bee2aef07e9c26e8070096fbe84a3d4d3eb0da069b5d76db

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# apt packages float within the Ubuntu release at build time (Git included);
# everything else below is pinned by version.
# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git sudo \
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
