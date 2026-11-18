# Core image: the toolchains every other image here is built on, also used directly as a CI job container.
# The default user stays root (no USER line), because GitHub Actions job containers expect it.
FROM ubuntu:26.04@sha256:d66b366dac61b575bee2aef07e9c26e8070096fbe84a3d4d3eb0da069b5d76db

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# apt packages float within the Ubuntu release at build time (Git included);
# everything else below is pinned by version.
# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git gnupg sudo unzip xz-utils \
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
 && curl -fsSL "$base/sha256sums.asc" | grep " \*$f\$" | (cd "$d" && sha256sum -c -) \
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
 && curl -fsSL "$base/SHASUMS256.txt" | grep " bun-linux-$b.zip\$" | (cd "$d" && sha256sum -c -) \
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
 && curl -fsSL "$base/cmake-${CMAKE_VERSION}-SHA-256.txt" | grep " $f\$" | (cd "$d" && sha256sum -c -) \
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
