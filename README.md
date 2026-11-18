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

Python through `uv`, Bun, CMake, Ninja, Git, Git LFS, GitHub CLI, fish and jq, plus the Claude Code and OpenCode
command-line tools. There is no Node.js; Bun covers that need. Every tool is pinned by version (Git and jq float
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
**Coder template** kept beside it in `images/coder-template/`. There is no dev container nested inside. Nothing
else is installed in it: the agent itself is fetched from the Coder server at each start, and the browser editor
comes from the template.

**The Coder host must have [sysbox](https://github.com/nestybox/sysbox) installed.** The workspace container runs
under the sysbox runtime, and there is no privileged fallback: install sysbox before creating the first workspace.

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

### Coder template

The Coder template is `images/coder-template/template/`: `main.tf`, its `.terraform.lock.hcl`, and a `README.md`
that Coder shows on the template's page and whose front matter sets its name and description.

**Requirements on the Coder deployment:**

- **[sysbox](https://github.com/nestybox/sysbox) on the Docker host.** The container runs with
  `runtime = "sysbox-runc"` and the entrypoint exactly `/sbin/init`. There is no privileged fallback: without
  sysbox, every workspace fails to start. The template's description in Coder says so too.
- A Docker host reachable by the provisioner (`docker_socket` template variable, empty for the default) on Linux.
- A **wildcard access URL** (`CODER_WILDCARD_ACCESS_URL`) for the OpenCode button. OpenCode's web UI cannot run
  under a path prefix, so it is a subdomain app; without wildcards the button does not open.

What a workspace gets:

- One parameter, the repository URL. The startup script clones it into `/home/dev/<repository>` if there is no
  checkout there yet, exports `REPO_DIR`, then imports its whole environment into `dev`'s systemd user manager
  and starts `agent-services.target` (ADR 0002). If the clone fails, the script says so in its log, still hands
  over, and then fails, so Coder flags it; the agent services keep retrying until you clone the repository by hand.
- VS Code Desktop (the agent's built-in button) and VS Code in the browser (Coder's `code-server` registry
  module, with both the module and code-server pinned). Both open `REPO_DIR`.
- An OpenCode button for the owner only, health-checked on `http://localhost:4096/`.
- Git identity (`GIT_AUTHOR_*`, `GIT_COMMITTER_*`) from the Coder account's name and email. `git push` and `gh`
  use a `GITHUB_TOKEN` Coder secret through the image's credential helper.
- Three volumes per workspace, kept across rebuilds and deleted with the workspace: `/home/dev`,
  `/var/lib/docker` and `/var/lib/containerd`. Nothing else persists: the container is recreated at every start.

**OpenCode's password.** OpenCode always asks for a password (user `opencode`) on top of Coder's own sign-in.
Each user defines it once as a Coder secret `OPENCODE_PASSWORD`, which reaches the server like any other secret.
The template deliberately does not generate one: a secret the user picks is one they know and can type, it is the
same in all their workspaces, it stays out of the Terraform state, and nothing in the template competes with the
user's own secret. Without the secret, OpenCode makes up a new password at every start and logs it
(`journalctl --user -u opencode | grep password`).

**First-time setup for a user:** define `GITHUB_TOKEN` (for private repositories and `git push`) and
`OPENCODE_PASSWORD` as Coder secrets, create the workspace, then run `claude` in the repository, accept the trust
prompt and `/login` with a claude.ai subscription. Remote control comes up on its next retry, within 15 seconds.
There is no way to grant the trust prompt ahead of time; `claude auth login` alone is not enough.

**Pushing the template by hand.** Nothing pushes it automatically. From a clean checkout (dot-directories such as
`.terraform/` are not uploaded):

```sh
coder login https://coder.example.com
coder templates push plume-works -d images/coder-template/template -m "<commit or change>" -y
```

The first push creates the template; later pushes add a version and make it active. The name, display name and
description come from the template README's front matter on every push.

**The image digest.** `main.tf` pins `ghcr.io/plume-works/coder-template:edge@sha256:<digest>`, and Renovate's
weekly "plume-works images" pull request moves it. **Until the image is first published, the digest is a
placeholder of zeros**: before the first push, replace it with the digest of `edge`
(`docker buildx imagetools inspect ghcr.io/plume-works/coder-template:edge`) or merge Renovate's pull request.
A template and the image it names change together: a change to either gets the check below before merge.

**Validating locally** (what CI's lint workflow runs):

```sh
T="docker run --rm -u $(id -u):$(id -g) -e HOME=/tmp -v $PWD:/w -w /w hashicorp/terraform:1.17.2 -chdir=images/coder-template/template"
$T fmt -check -diff && $T init -backend=false -input=false && $T validate
```

**Manual check on a real Coder deployment** (CI has neither Coder nor sysbox). Push the template under a scratch
name, create a workspace from a repository you can push to, and check:

1. The build log shows the container created with runtime `sysbox-runc`; the agent connects, and the startup
   script finishes. `systemctl --user status agent-services.target opencode claude-remote-control` shows the
   target active.
2. A secret reaches a service: define a Coder secret (say `PROBE_SECRET`), restart the workspace, and
   `systemctl --user show-environment | grep PROBE_SECRET` and
   `tr '\0' '\n' < /proc/$(systemctl --user show -p MainPID --value opencode)/environ | grep PROBE_SECRET` both
   find it.
3. `git commit` shows your Coder name and email; `git push` works with only the `GITHUB_TOKEN` secret.
4. A killed service restarts: `systemctl --user kill -s KILL opencode`, then within seconds it is active again
   with a new PID, and the OpenCode button works (after `OPENCODE_PASSWORD`).
5. VS Code Desktop and code-server open the repository.
6. Home survives a rebuild: write a file in `~`, stop and start the workspace (or update it to a new template
   version), and the file and a `docker pull`ed image are still there.
7. Stopping the workspace finishes within the 60-second grace period, without Docker killing the container.

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
images/coder-template/smoke.sh ghcr.io/plume-works/coder-template:ci
images/devcontainer-base/smoke.sh ghcr.io/plume-works/devcontainer-base:ci
```

The devcontainer base image's smoke test runs the devcontainer CLI (pinned in the script) through `npx`, or
`bunx` where there is no Node, and needs `jq` (every image here has it) and a Docker daemon that sees the local
`/tmp`.

Each image lives in `images/<name>/` with its `Dockerfile` and `smoke.sh`; `docker-bake.hcl` lists them, and
`.github/workflows/images.yml` builds, tests and publishes them all.

## Developing this repository

This repository is developed inside its own devcontainer base image, so the image gets continuous real use. Its
`.devcontainer.json` names `ghcr.io/plume-works/devcontainer-base:edge@sha256:<digest>` with the privileged-mode
snippet above, and no docker-in-docker Feature; Renovate proposes the digest bumps. Inside it, the commands under
[Building and testing locally](#building-and-testing-locally) work as they are: the image's own Docker engine
builds the images and runs their smoke tests. (Until the devcontainer base image is first published,
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
- Terraform providers (and the template's `.terraform.lock.hcl`) and modules, and image digests (ours included,
  grouped into one weekly pull request) in `.devcontainer.json` and the Coder template;
- other versions in the Coder template, pinned as a quoted attribute value directly below a `# renovate:`
  comment (`datasource`, `depName`, optional `extractVersion`), like code-server's `install_version`.

Apt packages, Git included, are not pinned: they float within the Ubuntu release and update whenever an image
is rebuilt.

## Linting

`.github/workflows/lint.yml` runs hadolint (ignores in `.hadolint.yaml`), shellcheck and actionlint (config in
`.github/actionlint.yaml`), and Terraform's `fmt -check` and `validate` on the Coder template (see
[Coder template](#coder-template) for that command), on every pull request; any finding fails it. Locally, from
the repository root:

```sh
docker run --rm -i -v "$PWD/.hadolint.yaml:/.config/hadolint.yaml" hadolint/hadolint:v2.15.1 < images/core/Dockerfile
docker run --rm -v "$PWD:/mnt" -w /mnt --entrypoint sh koalaman/shellcheck-alpine:v0.11.0 .github/scripts/shellcheck-all.sh
docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.12
```
