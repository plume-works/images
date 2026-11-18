# Images

Container images published by plume-works for running and developing software with coding agents.
See [GLOSSARY.md](GLOSSARY.md) for the vocabulary and [docs/adr/](docs/adr/) for the decisions behind them.

## Core image

`ghcr.io/plume-works/core`, for `linux/amd64` and `linux/arm64`. CI jobs use it directly and every other image
here is built on it. The default user is root; a non-root user `dev` (UID 1000, passwordless sudo) exists for
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

## Core systemd image

`ghcr.io/plume-works/core-systemd`: the core image with systemd as PID 1 and the Docker engine run as a
service. It is the parent of the Coder template image and the devcontainer base image and holds everything about
booting. Run it with its own entrypoint (`/sbin/init`) under sysbox or in privileged mode, with volumes for the
engine's storage at `/var/lib/docker` and `/var/lib/containerd`. Never share those volumes between two running
containers.

```sh
docker run -d --privileged -v /var/lib/docker -v /var/lib/containerd ghcr.io/plume-works/core-systemd@sha256:<digest>
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

`ghcr.io/plume-works/coder-template`: the core systemd image plus the Coder agent unit and the agent services.
The Coder template in `images/coder-template/` runs it directly as the one workspace container, under sysbox;
there is no dev container nested inside. It needs nothing else installed in it: the agent itself is fetched
from the Coder server at each start, and the browser editor comes from the template.

How a workspace starts (ADR 0002):

1. The template uploads two files before the container starts: the agent's init script to
   `/etc/coder/agent-init.sh` and its token to `/etc/coder/agent-token` (owned by `dev`, mode 0600).
2. systemd boots, and `coder-agent.service` runs the init script as `dev`. The agent reads its token from the
   file, and `XDG_RUNTIME_DIR=/run/user/1000` lets everything it launches reach `dev`'s systemd user manager.
   Without the init script (a plain `docker run`) the unit is skipped.
3. The template's startup script clones the repository, sets `REPO_DIR` to its path, and hands over:
   ```sh
   systemctl --user import-environment $(compgen -e)
   systemctl --user start agent-services.target
   ```
4. `agent-services.target` pulls in two user units, which systemd restarts whenever they stop. Nothing
   starts the target at boot.
   - `opencode.service`: `opencode serve` on `127.0.0.1:4096` (API and web UI), in `REPO_DIR`. OpenCode
     always asks for a password (user `opencode`); define a Coder secret `OPENCODE_PASSWORD`. Without one it
     makes up a new password at each start and logs it (`journalctl --user -u opencode`).
   - `claude-remote-control.service`: `claude remote-control --spawn worktree` in `REPO_DIR`, so each remote
     session gets its own worktree. It opens no port. It needs a claude.ai subscription sign-in and a trusted
     repository, and until then it exits and is retried every 15 seconds. **First-time setup:** run `claude`
     in the repository, accept the trust prompt and `/login`; remote control starts on its next retry. The
     service answers remote control's one-time "Enable Remote Control?" question itself.

Every Coder secret reaches both services, with one exception: `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN` and
`CLAUDE_CODE_OAUTH_TOKEN` are kept from remote control, which refuses to start while one is set. A new or
rotated secret takes effect on workspace restart. Logs: `journalctl -u coder-agent` and
`journalctl --user -u opencode -u claude-remote-control`.

To try it without Coder: `images/coder-template/smoke.sh <image>` boots it in privileged mode with a stand-in
for the agent and checks the hand-off.

## Devcontainer base image

`ghcr.io/plume-works/devcontainer-base`: the core systemd image plus a devcontainer metadata label, for a dev
container opened from local VS Code. The label sets the remote user to `dev`, installs the Claude Code VS Code
extension, and sets `overrideCommand: false` so that systemd stays PID 1. It has no lifecycle commands and no
mounts. Inside you get systemd, a Docker engine run as a service, and every tool and agent of the core image.

Name it in the `image` field of your `devcontainer.json`, pinned by digest, and add one of the two snippets below.
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
  "image": "ghcr.io/plume-works/devcontainer-base@sha256:<digest>",
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
  "image": "ghcr.io/plume-works/devcontainer-base@sha256:<digest>",
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
`bunx` where there is no Node, and needs a Docker daemon that sees the local `/tmp`.

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
