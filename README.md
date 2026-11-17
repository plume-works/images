# images

Container images for development work. `core` holds the shared tools: git,
`gh`, Docker, `uv`, Bun, Claude Code, OpenCode and a few basics. It has no
entrypoint and nothing specific to one host. Later images each build on `core`
from their own directory.

| Image | Pull |
|---|---|
| `core` | `docker pull ghcr.io/plume-works/core:edge` |

`edge` follows `main`; every build is also tagged with its full commit SHA.
Platforms: `linux/amd64`, `linux/arm64`.

## Build and test locally

```sh
docker buildx bake core
core/test.sh ghcr.io/plume-works/core:edge          # all checks
core/test.sh ghcr.io/plume-works/core:edge tools    # tools only
core/test.sh ghcr.io/plume-works/core:edge docker   # Docker daemon only
```

The `docker` checks start containers with `--privileged`.

## Docker inside the container

The Docker engine is installed but not started. To use it, call
`start-dockerd` from your own startup. It needs a privileged container or
sysbox, returns once the daemon answers, and does nothing if one is already
running.

Every container made from `core` gets an anonymous volume at
`/var/lib/docker`, whether or not it starts Docker.

## Design

See [the core image design](docs/superpowers/specs/2026-11-17-core-image-design.md)
and the decisions in [docs/adr/](docs/adr/).
