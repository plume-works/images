# Core image alignment design

Brings the `core-images-try2` branch in line with the spec in
[issue 4](https://github.com/plume-works/images/issues/4), fixes the defects
listed in `docs/handoff.md`, and replaces the shell test with a pytest suite
(ADR-0010). Scope is the core image and the repo's initial setup (CI, Renovate,
docs). No other image is built here.

Lines marked *(Claude's call)* were not decided by Anton. They are defaults,
open to change.

## Why

The core image was built several times on different branches to compare ways of
working, and the results disagree. Issue 4 is the fullest spec and was built as
[PR 18](https://github.com/plume-works/images/pull/18). This branch is the one
being carried forward, so it has to agree with issue 4 before the other images
are added on top of it. A separate review also found defects here that were
never shown to Anton.

## Goals

- The core image matches issue 4, except where this document says otherwise.
- Every downloaded archive is checked against a sha256 committed in this repo,
  and every copied image is pinned by digest. apt repositories and npm are
  deliberate exceptions (see "Where each tool comes from").
- No version changes without a pull request that passes the tests.
- The tests are a pytest suite and cover what PR 18's smoke test covered.
- A pull request publishes a testable `pr-N` image; `main` publishes `edge`.

## Non-goals

- The core systemd, Coder template and devcontainer base images.
- A `uv`-managed Python, version pins for apt packages, Node.js.

## Anti-goals

- Anything installed under a home directory.
- A download whose checksum is fetched from the same server at build time.
  Anton: "downloading both tarbal and sha has zero protection for binary swap
  or mitm."
- A published image that is not the image the tests ran against.

## Sources of truth

Issue 4 is the spec. Where this document is silent, issue 4 decides. This
document overrides it in these places, each decided by Anton in this session:

| Issue 4 says | This branch does | Why |
|---|---|---|
| One shell smoke script, no framework | pytest through `uv` | ADR-0010 |
| Everything outside Ubuntu's apt is version-pinned | gh and Docker float from their vendor apt repos | "gh and docker come from custom apt repo, so apt rules apply" |
| Python through `uv`, installed system-wide | Ubuntu's `python3` only | "swapping system python is a cry for problems"; users run `uv run` |
| Hosted Renovate app, no Renovate workflow, no custom pinning scripts | Self-hosted Renovate with one post-upgrade script | Baked hashes must be updated and verified in the same commit |
| Docs are README, glossary and ADRs, no plans | `docs/superpowers/` specs and plans are kept | The superpowers workflow is used for building |

Both references are public and readable without `gh`:

- issue 4: `curl -s https://api.github.com/repos/plume-works/images/issues/4`
- PR 18: `git fetch origin pull/18/head:pr-18`

Issue 4 does not settle these, so they are *(Claude's calls)*: no bare
`python` command, only `python3`; no `WORKDIR`; `unzip` and `xz-utils` are not
installed, since nothing needs them.

`GLOSSARY.md` does not exist on this branch yet. The one term in scope is
**Core image**; use PR 18's wording (`git show pr-18:GLOSSARY.md`, or fetch
`refs/pull/18/head`).

## Approaches

1. **Patch this branch's Dockerfile toward issue 4.** Chosen. Anton prefers how
   this branch takes tools from official images by digest, and its CI already
   pins actions by SHA.
2. **Adopt PR 18's core wholesale.** Rejected by Anton. PR 18 downloads each
   tarball and its checksum from the same server, which protects against
   nothing.
3. **Fix only the handoff items.** Rejected: core would still disagree with
   issue 4 on the default user, the shell, OpenCode's version and the tool list.

PR 18 is still the reference for the starter script, the test coverage and the
workflow skeleton.

## The image

### Layout

`core/` moves to `images/core/`. `start-dockerd` is renamed `start-docker`.
The bake file, the workflows and the README follow.

`images/core/.dockerignore` ignores everything and re-admits only the files the
Dockerfile copies, so tests and caches never enter the build context.

### User

- The image's default user is root. There is no `USER` line.
- The stock `ubuntu` user is deleted and `dev` is created fresh: uid and gid
  1000, bash as its shell, passwordless sudo, member of the `docker` group.
- fish is installed but is nobody's default shell.

### Where each tool comes from

| Source | Tools | Pin |
|---|---|---|
| Ubuntu apt | Git, Git LFS, CMake, Ninja, fish, `python3`, `build-essential`, `ripgrep`, `jq`, `less`, `curl`, `sudo`, `ca-certificates`, `gnupg`, `procps` | floats with the base image digest |
| Vendor apt repos | gh; Docker engine, CLI, Buildx, Compose | floats |
| Official image, `COPY --from` | Bun (`oven/bun`) | image digest |
| GitHub release archive | `uv` (`astral-sh/uv`), OpenCode 2 (`anomalyco/opencode`) | exact version plus a sha256 per architecture, baked into the Dockerfile |
| npm through Bun | Claude Code | exact version |

- `python3` is listed explicitly. It is the system Python and is not replaced.
  No `uv`-managed Python is installed.
- No Node.js.
- `uv` and OpenCode: the Dockerfile downloads the archive for the build's
  architecture and fails unless its sha256 equals the baked value. The version
  and both hashes sit together as `ARG`s. *(Claude's call: the exact `ARG`
  names and layout, as long as the post-upgrade script can find them.)*
- OpenCode moves from 1.19 to the 2.x line. Its npm package (`@opencode/cli`)
  does not install under Bun, which is why it is a release archive.
- Claude Code keeps today's Bun install into `/usr/local`. npm stops allowing a
  version to be removed after three days, which is the same wait Renovate
  applies.
- Use the newest versions that are at least three days old when building this.
  *(Claude's call.)*
- **The exceptions to anchoring, decided by Anton.** The vendor apt repos keep
  fetching their signing key at build time, as today; "apt rules apply". Claude
  Code has no hash in the repo; the exact version and the three-day wait are
  the protection. The new ADR says so.
- **If Claude Code from Bun cannot pass the tests** (bare, self-update off),
  stop and ask Anton. Do not add Node.js or switch to the native binary
  unasked. A check during design showed the Bun install runs without Node.
- **User tool directories are not put on `PATH`.** The handoff suggests adding
  `/home/dev/.local/bin` and `/home/dev/.bun/bin`. Anton dropped this: all
  tools are system-wide, and home directories first on `PATH` would let a home
  volume shadow the image's tools.

### Rules for the image

- **Nothing under a home directory.** Every tool resolves outside `/root` and
  `/home`. The homes of root and `dev` hold only shell start-up files.
- **Nothing updates itself.** Turned off for both agents in three places:
  - the image's `ENV` (`DISABLE_AUTOUPDATER`, `DISABLE_UPDATES`,
    `OPENCODE_DISABLE_AUTOUPDATE`), for CI jobs and `docker run` or `exec`
  - `/etc/claude-code/managed-settings.json`, which a user cannot override
  - `/etc/environment`, for `su -l` and SSH logins
- **Agents are bare.** No settings beyond the above, no plugins, skills, MCP
  servers or credentials.
- **git credentials.** `gh` is git's system-wide credential helper for
  `github.com` and `gist.github.com`, as in PR 18.
- **Volume.** Only `/var/lib/docker` is declared. `/var/lib/containerd` waits
  for the core systemd image.
- **Labels.** Remove the empty `org.opencontainers.image.version` label. Leave
  Ubuntu's `image.created` date alone.

### `start-docker`

Take PR 18's script whole (`git show pr-18:images/core/start-docker`). It
already:

- does nothing when an engine answers
- refuses to start with `/var/lib/docker` on the overlay filesystem, naming
  what to mount
- sets up cgroup v2 so inner containers can use resource limits (on this
  branch today `docker run --memory 64m` exits 125)
- locks against two concurrent first calls
- starts `docker.service` when systemd is PID 1
- appends to `/var/log/dockerd.log`

Add one fix it lacks: when the timeout fires, stop the `dockerd` the script
started before exiting 1, so a retry does not launch a second one. A daemon the
script did not start is left alone.

## Tests

- `images/core/test_core.py`, run as `uv run pytest images/core`.
- A root `pyproject.toml` and `uv.lock` pin pytest.
- `--image <ref>` selects the image; the default is
  `ghcr.io/plume-works/core:edge`, which a local `docker buildx bake` produces.
- Read-only checks share one container for the whole run. Engine checks share
  one privileged container. Tests that need a broken setup (overlay storage, a
  start timeout) each get their own.
- Engine tests are marked `privileged`; `-m "not privileged"` skips them.
- Tests check behaviour of the built image. They do not read the Dockerfile.
- Failures say what was seen (the uid, the shell, the missing tool).

Coverage, as root and as `dev` where it applies:

- default user is root; `dev` is uid and gid 1000 with bash and passwordless
  sudo; no entrypoint; the `image.source` label
- every tool answers and resolves outside a home directory; the homes are bare
- `python3` is `/usr/bin/python3`; no `node`, `npm` or `npx`
- OpenCode reports a 2.x version
- git gets a credential from `GH_TOKEN` or `GITHUB_TOKEN` through `gh`, and
  fails without prompting when there is none
- the agents are bare (no MCP servers, plugins or sign-in)
- self-updating is off as root, as `dev`, and in a fresh `su -l dev` login
- the engine is not running by default; `start-docker` brings it up; a second
  call is a no-op; `dev` can use it without sudo; a container runs; a container
  with a memory limit runs; `/var/lib/docker` is a mount
- `start-docker` refuses overlay storage and says what to mount
- `start-docker` fails within its timeout when unprivileged and leaves no
  `dockerd` behind

### The inner engine's test image

The inner engine pulls a `hello-world` mirror from GHCR, not Docker Hub, to
stay clear of Docker Hub's anonymous rate limit.

- `ghcr.io/plume-works/hello-world`, a public package, copied once by hand by
  Anton. No workflow maintains it.
- The tests reference it by digest. Renovate ignores it.
- In CI the inner engine logs in to `ghcr.io` with the runner's token. Without
  a token (fork pull requests, a laptop) it pulls anonymously.
- The digest is Docker Hub's index digest for `hello-world`, which the copy
  below preserves for both architectures. On 2026-11-19 it is
  `sha256:1e4c05b897a751332ce85c7e9449da2d93514ea2dea6dbb0e2753c9e949b2bfa`.

  ```sh
  docker buildx imagetools create \
    -t ghcr.io/plume-works/hello-world:latest \
    hello-world@sha256:1e4c05b897a751332ce85c7e9449da2d93514ea2dea6dbb0e2753c9e949b2bfa
  ```

- *(Claude's calls)* The mirror by digest is the tests' default and what CI
  uses. The image and the token are test options, so the suite can run against
  plain `hello-world` locally before the mirror exists. CI's engine tests fail
  until Anton has made the copy; ask him to do it before the first push.

### `uv` on the host

`uv` is added to this repo's dev container and to CI, pinned in both.
*(Claude's call: how.)*

## Pipeline

Three workflows, cut down from PR 18 for one image, keeping this branch's
habits: actions pinned by SHA, `persist-credentials: false`, `contents: read`
by default.

**`build.yml`** (pull requests, pushes to `main`, manual):

- Each architecture builds and tests on its own native runner
  (`ubuntu-26.04`, `ubuntu-26.04-arm`), with a build cache per architecture.
- Publishing happens only when both pass:
  - a pull request from this repo publishes `pr-N`, made from the two tested images pushed as `pr-N-amd64` and `pr-N-arm64`
  - a push to `main` moves `edge`
  - a pull request from a fork publishes nothing
- The image each job pushes is the tested one, loaded and tagged, not a rebuild.
- Besides `edge` and `pr-N`, only the per-architecture `<tag>-<arch>` tags are published. The commit-SHA tag is dropped.

**`pr-cleanup.yml`**: deletes `pr-N`, `pr-N-amd64` and `pr-N-arm64` when the pull request closes.

**`lint.yml`**: hadolint, shellcheck and actionlint on every pull request.

## Renovate

- Self-hosted in a workflow, authenticating as the `plume-works-renovate`
  GitHub App so its pull requests trigger CI. Borrow the shape of
  `plume-works/agent-devcontainer`'s `.github/workflows/renovate.yml`: App
  token, queued and never cancelled runs, one allowed post-upgrade command.
- Triggers: daily, pushes to `main`, manual.
- Leave behind from that repo: running inside its own dev container image, the
  pre-commit coupling, the dashboard-edit triggers, the Ansible pin managers.
- Secrets: `RENOVATE_APP_CLIENT_ID`, `RENOVATE_APP_PRIVATE_KEY`.
- The Renovate version is pinned and kept current by Renovate itself.
- *(Claude's call)* Renovate runs directly on the runner, as
  `bunx renovate@<version>` the way agent-devcontainer does, with Bun and `uv`
  installed on the runner by pinned setup actions. The post-upgrade command
  then runs on the runner, where `uv run` exists. Do not use a containerised
  Renovate action: the script would run inside its container, without `uv`.
- The reference repo is public: clone
  `https://github.com/plume-works/agent-devcontainer` and read
  `.github/workflows/renovate.yml` and `.github/renovate.json`.
- Config is a root `renovate.json`. The file on `main` is the hosted app's
  default and is replaced; `.github/renovate.json` is removed.
- ADR-0009's policy stays: every update waits 3 days, an `x.y.0` release waits
  10, and updates merge on their own once the build passes.
- The `uv` regex manager and its two package rules go; `uv` now reads its
  version from GitHub releases like OpenCode.
- The Ubuntu major/minor hold is scoped to the Docker datasource.

### The post-upgrade script

One script, run by Renovate when it bumps `uv` or OpenCode. For the new
release it:

1. reads the sha256 GitHub recorded for the two Linux archives
2. refuses unless GitHub marks the release immutable
3. writes both hashes into the Dockerfile, in the same commit as the version

If it refuses, the branch fails and nothing merges. Both upstreams publish
immutable releases today.

GitHub's release API returns `immutable` on the release and `digest` on each
asset. Both repos are public, so the script works without a token; it uses one
when the environment provides it, to avoid the anonymous rate limit.

*(Claude's calls)* It is Python, run with `uv run`, lives under `scripts/`,
and has pytest unit tests that fake GitHub's responses.

## Docs

- Rewrite ADR-0008 for the user decisions.
- New ADR: nothing under home, nothing self-updates.
- New ADR: self-hosted Renovate and baked hashes, including that it reverses
  issue 4.
- Update ADR-0009 where it describes the `uv` workaround.
- `GLOSSARY.md` with **Core image**.
- README: new paths and commands, the admission rule, how versions update.
- Delete `docs/handoff.md` as the last task, once its items are done or listed
  below.
- The older spec and plan under `docs/superpowers/` stay.

The admission rule, from issue 4: a build toolchain is added to the core image
only when at least two plume-works repositories need it in CI; interactive
conveniences are added at the maintainer's discretion.

ADRs and the glossary are written with the `domain-modeling` skill.

## Branch

Merge `main` into this branch (it is already pushed, so no rebase).

## For Anton to do

None of these can be done from the build session.

- Require `build (amd64)` and `build (arm64)` on `main`.
- Install the `plume-works-renovate` App on this repo and add its two secrets.
- Remove the hosted Renovate app from this repo.
- Copy `hello-world` to `ghcr.io/plume-works/hello-world` once and make the
  package public.
- Make the `core` package public after the first publish.

## Not verified by this work

- The publish path on `main`, until the first merge.
- A real Renovate run, including the post-upgrade script inside it.

## Review findings

The build's final report lists every finding a reviewer dismisses.

From earlier reviews:

| Finding | Outcome |
|---|---|
| `start-dockerd` leaves the daemon running on timeout | fixed here |
| `start-dockerd` overwrites its log | fixed here |
| `packages: write` on pull request builds | needed now, to publish `pr-N` |
| No check that a pushed digest is non-empty | the push step fails on an empty digest |
| CI pulls `hello-world` anonymously | fixed by the GHCR mirror |
| User tool directories on `PATH` (handoff) | dropped by Anton; all tools are system-wide |
| `docker info` calls are not time-bounded | stays dismissed |
| A non-numeric timeout gives no hint | stays dismissed |

## Left to the builder

Dockerfile layer order, the bake file's shape, the `ARG` names, fixture
structure, which action deletes `pr-N`, and how `uv` reaches the dev container.
