# images

Container images for development environments, built from this repo and
published to GitHub Container Registry. Images are host-neutral: they carry
tools, not editor or devcontainer configuration. Versions are pinned and kept
current by Renovate.

| Image | Pull | Contents |
|---|---|---|
| core | `ghcr.io/plume-works/core:edge` | Ubuntu 26.04, git, gh, Node 24, uv, Bun, Docker, Claude Code, OpenCode |

Tags are `edge` (latest `main`) and the full commit SHA. Platforms are
`linux/amd64` and `linux/arm64`.

## Build and test locally

```sh
docker buildx bake core
core/test.sh ghcr.io/plume-works/core:edge
```

The Docker tests start a nested daemon, so they need a host that allows
`--privileged`. Run only the tool checks with `core/test.sh <image> tools`.

## Using Docker inside a container

Docker is installed but not started. A consumer calls `start-dockerd` from its
own startup. The container must run privileged or under sysbox, and
`/var/lib/docker` needs a volume, because a nested dockerd cannot use overlay
on the container's overlay root filesystem.

## Design

See [docs/superpowers/specs/2026-11-17-core-image-design.md](docs/superpowers/specs/2026-11-17-core-image-design.md).
