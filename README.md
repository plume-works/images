# Images

Container images published by plume-works for running and developing software with coding agents.
See [GLOSSARY.md](GLOSSARY.md) for the vocabulary and [docs/adr/](docs/adr/) for the decisions behind them.

## Core image

`ghcr.io/plume-works/core`, for `linux/amd64` and `linux/arm64`. CI jobs use it directly and every other image
here is built on it. The default user is root; a non-root user `dev` (UID 1000, passwordless sudo) exists for
interactive use.

Pin it by digest. The only tags are `edge` (latest tested `main`) and `pr-N` (a pull request, deleted on close).

## Building and testing locally

```sh
docker buildx bake --load
images/core/smoke.sh ghcr.io/plume-works/core:ci
```

Each image lives in `images/<name>/` with its `Dockerfile` and `smoke.sh`; `docker-bake.hcl` lists them, and
`.github/workflows/images.yml` builds, tests and publishes them all.
