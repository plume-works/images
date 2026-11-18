# Images

Container images published by plume-works for running and developing software with coding agents.
See [GLOSSARY.md](GLOSSARY.md) for the vocabulary and [docs/adr/](docs/adr/) for the decisions behind them.

## Core image

`ghcr.io/plume-works/core`, for `linux/amd64` and `linux/arm64`. CI jobs use it directly and every other image
here is built on it. The default user is root; a non-root user `dev` (UID 1000, passwordless sudo) exists for
interactive use.

Pin it by digest. The only tags are `edge` (latest tested `main`) and `pr-N` (a pull request, deleted on close).

### Docker engine in a CI job

The core image has the Docker engine, CLI, Buildx and Compose; `dev` is in the `docker` group. A job container
does not run systemd, so `start-docker` starts the engine on demand and returns once it is ready. It does nothing
if an engine is already running, so calling it twice is safe. The container needs privileged mode, and a volume
at `/var/lib/docker`: the engine cannot start containers when its storage sits on the container's own overlay
filesystem, and `start-docker` refuses to start without it.

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/plume-works/core@sha256:<digest>
      options: --privileged --volume /var/lib/docker
    steps:
      - run: start-docker
      - run: docker run --rm hello-world
```

This engine is the job's own, isolated from the runner's: it starts with no images and nothing it builds or
pulls outlives the job. The engine logs to `/var/log/dockerd.log`; `START_DOCKER_TIMEOUT` (seconds, default 60)
bounds the wait. `dev` can run `start-docker` too (it uses passwordless sudo). Where systemd is PID 1, it just
starts `docker.service`.

## Building and testing locally

```sh
docker buildx bake --load
images/core/smoke.sh ghcr.io/plume-works/core:ci
```

Each image lives in `images/<name>/` with its `Dockerfile` and `smoke.sh`; `docker-bake.hcl` lists them, and
`.github/workflows/images.yml` builds, tests and publishes them all.

## How versions are updated

Everything this repository depends on is pinned, and a pin changes only through a pull request that passes
the same build, test and `pr-N` publish as any other. [Renovate](https://docs.renovatebot.com/) (the hosted
GitHub app, configured in [`renovate.json`](renovate.json)) opens those pull requests for:

- the Ubuntu base image, pinned by tag and digest in `images/core/Dockerfile`;
- every non-apt tool in a Dockerfile, pinned by an `ARG <NAME>_VERSION` directly below a `# renovate:` comment:
  ```dockerfile
  # renovate: datasource=github-releases depName=cli/cli extractVersion=^v(?<version>.+)$
  ARG GH_VERSION=2.105.0
  ```
  `datasource` and `depName` are required; `packageName`, `versioning` and `extractVersion` are optional, in that
  order. The value carries no `v` prefix;
- GitHub Actions and the linter images in `.github/workflows/`;
- Terraform providers and modules, and image digests (ours included, grouped into one weekly pull request) in
  `.devcontainer.json` and the Coder template.

Apt packages, Git included, are not pinned: they float within the Ubuntu release and update whenever an image
is rebuilt.

## Linting

`.github/workflows/lint.yml` runs hadolint (ignores in `.hadolint.yaml`), shellcheck and actionlint (config in
`.github/actionlint.yaml`) on every pull request; any finding fails it. Locally, from the repository root:

```sh
docker run --rm -i -v "$PWD/.hadolint.yaml:/.config/hadolint.yaml" hadolint/hadolint:v2.15.1 < images/core/Dockerfile
docker run --rm -v "$PWD:/mnt" -w /mnt --entrypoint sh koalaman/shellcheck-alpine:v0.11.0 .github/scripts/shellcheck-all.sh
docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.12
```
