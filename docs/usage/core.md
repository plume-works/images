# Core image

`ghcr.io/plume-works/core`, for CI authors: the `container:` of a CI job, pinned by tag and digest
(`ghcr.io/plume-works/core:edge@sha256:<digest>`). Every other image here is built on it.

## What is in it

- Ubuntu's Python (`python`, `python3`) and `uv`, Bun (there is no Node.js), CMake, Ninja, Git, Git LFS, GitHub CLI, fish, jq, tmux and btop.
- The Claude Code and OpenCode command-line tools, installed bare: no settings, plugins, skills, MCP servers or
  credentials, and they never update themselves.
- The Docker engine, CLI, Buildx and Compose.

Every tool is installed system-wide, so it works wherever a CI system points `HOME`. The default user is root; a
non-root user `dev` (UID 1000, passwordless sudo, in the `docker` group) exists for interactive use.

git authenticates to GitHub through the GitHub CLI wherever `GH_TOKEN` or `GITHUB_TOKEN` is set.

apt installs from the same dated Ubuntu archive snapshot the image was built from, so `apt-get install` in a job
gets the versions of that day; a newer image moves the snapshot.

## Docker in a CI job

A job container does not run systemd, so `start-docker` starts the engine and returns once it is ready (calling it
again is harmless). The container needs privileged mode and a volume for the engine's storage:

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/plume-works/core:edge@sha256:<digest>
      options: --privileged
      volumes:
        - /var/lib/docker
    steps:
      - run: start-docker
      - run: docker run --rm hello-world
```

The engine is the job's own: it starts with no images, and nothing it builds or pulls outlives the job. It logs
to `/var/log/dockerd.log`; `START_DOCKER_TIMEOUT` (seconds, default 60) bounds the wait.

## The engine's storage

The engine cannot start containers with its storage on the container's own overlay filesystem
([ADR 0014](../adr/0014-no-engine-storage-volumes.md)):

- Under sysbox, mount nothing at `/var/lib/docker` or `/var/lib/containerd`: sysbox gives each container its own.
- In privileged mode, mount a volume at `/var/lib/docker`, and under systemd at `/var/lib/containerd` too (an
  anonymous one, a named one to keep images and cache, or a Kubernetes `emptyDir`). Without one, `start-docker`
  refuses to start and says so.
- Never share these volumes between two containers.
