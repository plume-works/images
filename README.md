# images

Container images for Plume Works development environments. Each image lives in its own directory under `images/` and is built from a plain Dockerfile; a GitHub Actions workflow builds and publishes them for `linux/amd64` and `linux/arm64`, and Renovate keeps the pins current.

| Image | Pull name |
|---|---|
| `core` | `ghcr.io/plume-works/core:edge` |

A pull request from this repo publishes `ghcr.io/plume-works/core:pr-N` (removed when the PR closes); `main` publishes `edge`. Nothing else is tagged.

## Build and test locally

```sh
docker buildx bake core
uv run pytest images/core
```

`--image <ref>` tests another image. Tests that start a daemon need a host whose Docker allows privileged containers; `-m "not privileged"` skips them.

## Docker inside a container

The image does not start a Docker daemon on its own. A consumer runs `start-docker` when it wants one, in a container that is privileged or runs under sysbox. Every container gets an anonymous volume at `/var/lib/docker`.

## How versions update

Renovate runs in GitHub Actions and opens a pull request for each update, after a 3-day wait (10 days for an `x.y.0`). `uv` and OpenCode are release archives checked against sha256 hashes committed in the Dockerfile; `scripts/bake_hashes.py` refills them with each bump. Nothing in the image updates itself. See ADR-0011 and ADR-0012.

## What goes in the core image

A build toolchain is added only when at least two plume-works repositories need it in CI. Interactive conveniences are added at the maintainer's discretion.

## Design

See [the core image alignment design](docs/superpowers/specs/2026-11-19-core-image-alignment-design.md). Longer-lived decisions are in [`docs/adr/`](docs/adr/), terms in [`GLOSSARY.md`](GLOSSARY.md).

## License

MIT, see [LICENSE](LICENSE). Vendored skills in `.agents/skills/` carry their own licenses.
