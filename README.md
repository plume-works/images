# Images

Container images published by plume-works for running and developing software with coding agents.
See [GLOSSARY.md](GLOSSARY.md) for the vocabulary and [docs/adr/](docs/adr/) for the decisions behind them.

This repository publishes four images and nothing else. Each is built on the one before it, from the same
commit, so every tool is in the core image and CI, workspaces and dev containers always have the same toolchain.

| Image | Who it is for | How to use it |
|---|---|---|
| [Core image](#core-image) `ghcr.io/plume-works/core` | CI authors | The `container:` of a CI job, pinned by digest |
| [Core systemd image](#core-systemd-image) `ghcr.io/plume-works/core-systemd` | Builders of the two images below | `FROM` it; run it with its own entrypoint under sysbox or in privileged mode |
| [Coder template image](#coder-template-image) `ghcr.io/plume-works/coder-template` | Coder workspace users and host administrators | Through the Coder template beside it. **The Coder host must have sysbox.** |
| [Devcontainer base image](#devcontainer-base-image) `ghcr.io/plume-works/devcontainer-base` | Developers using a dev container from local VS Code | The `image` of a `devcontainer.json`, plus one of two snippets |

All four are published for `linux/amd64` and `linux/arm64`. The only tags are `edge` (the latest tested `main`;
it moves on all four images together, and only when every image passes on both architectures) and `pr-N` (a pull
request, deleted when it closes). There are no version tags: pin by tag and digest, `<image>:edge@sha256:<digest>`,
and let Renovate propose digest bumps.

Nothing in any image updates itself. A version changes only through a pull request that passes the tests (see
[How versions are updated](#how-versions-are-updated)).

**Not a goal for now:** an image deployed as a service that takes coding requests from agents (an agent-request
service image). It is a known future image, but nothing here is designed for it; the four images above should
not grow features in anticipation of it.

## Core image

`ghcr.io/plume-works/core`, for CI authors. CI jobs use it directly and every other image here is built on it. The default user is root; a non-root user `dev` (UID 1000, passwordless sudo) exists for
interactive use.

### Toolchains and agents

Python through `uv`, Bun, CMake, Ninja, Git, Git LFS, GitHub CLI and fish, plus the Claude Code and OpenCode
command-line tools. There is no Node.js; Bun covers that need. Every tool is pinned by version (Git floats
with the Ubuntu release, as all apt packages do) and installed system-wide, never under a home directory, so it
works wherever a CI system points `HOME` and a persistent home volume never shadows a newer image's tools.

The agents are installed bare: no settings, plugins, skills, MCP servers or credentials. Self-updating is
turned off system-wide for both. git's system-wide credential helper for GitHub is the GitHub CLI, so git
authenticates wherever `GH_TOKEN` or `GITHUB_TOKEN` is set.

**Admission rule:** a build toolchain is added only when at least two plume-works repositories need it in CI.
Interactive conveniences are added at the maintainer's discretion. Anything else belongs in the repository
that needs it.

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
      image: ghcr.io/plume-works/core:edge@sha256:<digest>
      options: --privileged --volume /var/lib/docker
    steps:
      - run: start-docker
      - run: docker run --rm hello-world
```

This engine is the job's own, isolated from the runner's: it starts with no images and nothing it builds or
pulls outlives the job. The engine logs to `/var/log/dockerd.log`; `START_DOCKER_TIMEOUT` (seconds, default 60)
bounds the wait. `dev` can run `start-docker` too (it uses passwordless sudo). Where systemd is PID 1, it just
starts `docker.service`.

## Core systemd image

`ghcr.io/plume-works/core-systemd`: the core image with systemd as PID 1 and the Docker engine run as a
service. It is the parent of the Coder template image and the devcontainer base image and holds everything about
booting, written once so the two cannot drift apart. It is for building those images; to work in it, use one of
them instead. Run it with its own entrypoint (`/sbin/init`) under sysbox or in privileged mode, with volumes for the
engine's storage at `/var/lib/docker` and `/var/lib/containerd`. Never share those volumes between two running
containers.

```sh
docker run -d --privileged -v /var/lib/docker -v /var/lib/containerd ghcr.io/plume-works/core-systemd:edge@sha256:<digest>
```

- The default user is root, because systemd must run as root. `dev`'s systemd user manager runs from boot,
  without a login.
- Logs for every unit are in the journal (`journalctl`). journald does not read the kernel log.
- Nothing updates itself: the operating system's periodic update timers are masked.
- Once a week, a timer removes Docker images that no container uses and that were pulled or built more than a
  week ago, and build cache not used for a week. It never removes volumes or containers, stopped ones included.
- `docker stop` shuts systemd down, and the inner engine stops its containers first. Allow it more than the
  default 10 seconds (`docker stop -t 60`), because the inner engine waits 10 seconds for a container that
  ignores SIGTERM.

## Coder template image

`ghcr.io/plume-works/coder-template`, for Coder workspace users and the administrators of Coder hosts: the core
systemd image plus the Coder agent and the agent services, run directly as the one workspace container by the
**Coder template** kept beside it in `images/coder-template/`.

**The Coder host must have [sysbox](https://github.com/nestybox/sysbox) installed.** The workspace container runs
under the sysbox runtime, and there is no privileged fallback: install sysbox before creating the first workspace.

## Devcontainer base image

`ghcr.io/plume-works/devcontainer-base`: the core systemd image plus a devcontainer metadata label, for a dev
container opened from local VS Code. The label sets the remote user to `dev`, installs the Claude Code VS Code
extension, and sets `overrideCommand: false` so that systemd stays PID 1. It has no lifecycle commands and no
mounts. Inside you get systemd, a Docker engine run as a service, and every tool and agent of the core image.

Name it in the `image` field of your `devcontainer.json`, pinned by tag and digest, and add one of the two snippets below.
The image does not choose how it runs; you do (ADR 0001):

- **sysbox** (Linux hosts with [sysbox](https://github.com/nestybox/sysbox) installed): no privileged container.
- **Privileged mode** (macOS, or Linux without sysbox): Docker Desktop on macOS offers sysbox only in a paid tier.

Both snippets add a volume for the Docker engine's storage (`/var/lib/docker` and `/var/lib/containerd`; the inner
engine cannot run containers without them) and a volume for the whole home directory, so agent sign-ins and shell
history survive a rebuild. The home volume covers all of `/home/dev`, because the agents keep sign-in state in
more than one place under it. It is yours to keep, leave out, or replace with your own mount. A new home volume is
filled from the image's `/home/dev`.

With sysbox:

```jsonc
{
  "image": "ghcr.io/plume-works/devcontainer-base:edge@sha256:<digest>",
  "runArgs": ["--runtime=sysbox-runc"],
  "mounts": [
    "source=dc-${devcontainerId}-docker,target=/var/lib/docker,type=volume",
    "source=dc-${devcontainerId}-containerd,target=/var/lib/containerd,type=volume",
    "source=dc-${devcontainerId}-home,target=/home/dev,type=volume"
  ]
}
```

In privileged mode (this one is what the smoke test brings up):

<!-- smoke-test: privileged -->
```jsonc
{
  "image": "ghcr.io/plume-works/devcontainer-base:edge@sha256:<digest>",
  "privileged": true,
  "mounts": [
    "source=dc-${devcontainerId}-docker,target=/var/lib/docker,type=volume",
    "source=dc-${devcontainerId}-containerd,target=/var/lib/containerd,type=volume",
    "source=dc-${devcontainerId}-home,target=/home/dev,type=volume"
  ]
}
```

`${devcontainerId}` is stable for a workspace folder, so the volumes survive "Rebuild Container". Never share the
Docker volumes between two running containers.

Add your project's own tooling with Features or your own Dockerfile on top. Things to know:

- **Do not add the `docker-in-docker` Feature** (nor `docker-outside-of-docker`). The image already runs a Docker
  engine under systemd; a second engine, or the host's socket, would fight it over `/var/run/docker.sock` and
  its storage.
- Avoid Features whose entrypoint starts a daemon (`sshd`, for example): it starts before systemd and clashes
  with systemd's own units. Features that only install something work.
- On a Linux host whose user is not UID 1000, the devcontainer CLI changes `dev`'s UID to match it. Files in a
  home volume created before that change keep UID 1000.
- **Not supported:** GitHub Codespaces, and running this dev container nested inside a Coder workspace (use the
  Coder template image there instead). It is meant for local VS Code.

## Building and testing locally

```sh
docker buildx bake --load
images/core/smoke.sh ghcr.io/plume-works/core:ci
images/core-systemd/smoke.sh ghcr.io/plume-works/core-systemd:ci
images/devcontainer-base/smoke.sh ghcr.io/plume-works/devcontainer-base:ci
```

The devcontainer base image's smoke test runs the devcontainer CLI (pinned in the script) through `npx`, or
`bunx` where there is no Node, and needs `jq` and a Docker daemon that sees the local `/tmp`.

Each image lives in `images/<name>/` with its `Dockerfile` and `smoke.sh`; `docker-bake.hcl` lists them, and
`.github/workflows/images.yml` builds, tests and publishes them all.

## Developing this repository

This repository is developed inside its own devcontainer base image, so the image gets continuous real use. Its
`.devcontainer.json` names `ghcr.io/plume-works/devcontainer-base:edge@sha256:<digest>` with the privileged-mode
snippet above, and no docker-in-docker Feature; Renovate proposes the digest bumps. Inside it, the commands under
[Building and testing locally](#building-and-testing-locally) work as they are: the image's own Docker engine
builds the images and runs their smoke tests. The devcontainer base image's smoke test also needs `jq`, which
the images do not have: `sudo apt-get install -y jq` first. (Until the devcontainer base image is first published,
`.devcontainer.json` still uses a stock Ubuntu dev container.)

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
- tools a smoke script runs, pinned the same way by a `<NAME>_VERSION=` line (no `ARG`) in `smoke.sh`;
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
