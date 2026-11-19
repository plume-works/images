# images

Container images for Plume Works development environments. Each image lives in its own directory and is built from a plain Dockerfile; a GitHub Actions workflow builds and publishes them for `linux/amd64` and `linux/arm64`, and Renovate keeps the pins current.

| Image | Pull name |
|---|---|
| `core` | `ghcr.io/plume-works/core:edge` |

## Build and test locally

```sh
docker buildx bake core
uv run pytest images/core
```

`uv run pytest images/core` tests the built image (`--image` picks another). Tests that start a daemon need a host whose Docker allows privileged containers.

## Docker inside a container

The image does not start a Docker daemon on its own. A consumer runs `start-docker` when it wants one, in a container that is privileged or runs under sysbox. Every container gets an anonymous volume at `/var/lib/docker`.

## Design

See [the core image design](docs/superpowers/specs/2026-11-17-core-image-design.md). Longer-lived decisions are in [`docs/adr/`](docs/adr/).

## License

MIT, see [LICENSE](LICENSE). Vendored skills in `.agents/skills/` carry their own licenses.
