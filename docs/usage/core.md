# Core image

`ghcr.io/plume-works/core`, for CI authors: the `container:` of a CI job, pinned by tag and digest
(`ghcr.io/plume-works/core:edge@sha256:<digest>`). Every other image here is built on it.

## What is in it

- Ubuntu's Python (`python`, `python3`) and `uv`, Bun (there is no Node.js), CMake, Ninja, Git, Git LFS, GitHub CLI, fish and jq.
- The Claude Code and OpenCode command-line tools, installed bare: no settings, plugins, skills, MCP servers or
  credentials, and they never update themselves.
- The Docker engine, CLI, Buildx and Compose.

Every tool is installed system-wide, so it works wherever a CI system points `HOME`. The default user is root; a
non-root user `dev` (UID 1000, passwordless sudo, in the `docker` group) exists for interactive use.

git authenticates to GitHub through the GitHub CLI wherever `GH_TOKEN` or `GITHUB_TOKEN` is set.

## Docker in a CI job

A job container does not run systemd, so `start-docker` starts the engine and returns once it is ready (calling it
again is harmless). The container needs privileged mode and nothing else:

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/plume-works/core:edge@sha256:<digest>
      options: --privileged
    steps:
      - run: start-docker
      - run: docker run --rm hello-world
```

The engine is the job's own: it starts with no images, and nothing it builds or pulls outlives the job. It logs
to `/var/log/dockerd.log`; `START_DOCKER_TIMEOUT` (seconds, default 60) bounds the wait.

## The engine's storage

`/var/lib/docker` and `/var/lib/containerd` are declared volumes in this image and every image built on it
([ADR 0004](../adr/0004-engine-storage-declared-as-volumes.md)). What that means for you:

- A container run without `--rm` leaves anonymous volumes behind: remove it with `docker rm -v`, or run
  `docker volume prune` now and then. Mount named volumes there where the engine's images and cache should persist.
- A Dockerfile built on these images cannot add files under either path.
- A runtime that ignores image volumes (Kubernetes) needs a volume mounted at `/var/lib/docker`, and at
  `/var/lib/containerd` under systemd (an `emptyDir`, say). Without one, `start-docker` refuses to start and says so.
- Never share these volumes between two containers, not even with one that is still shutting down: under sysbox
  its mounts can outlive it ([ADR 0014](../adr/0014-coder-workspaces-drop-engine-storage.md)).
