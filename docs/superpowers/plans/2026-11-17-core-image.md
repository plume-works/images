# Core Image Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build, test and publish a host-neutral `core` container image with the agreed dev tools, plus Renovate upkeep.

**Architecture:** One directory per image. `core/Dockerfile` installs tools and nothing else; `core/start-dockerd` is an opt-in daemon starter; `core/test.sh` is the acceptance test, run locally and in CI. `docker-bake.hcl` is the single build entry point, so later consumer images can take the built core as a named context.

**Tech Stack:** Dockerfile, Docker Buildx Bake, POSIX `sh`, GitHub Actions, Renovate (hosted app).

**Spec:** `docs/superpowers/specs/2026-11-17-core-image-design.md`. Read it before any task.

## Global Constraints

- No `ENTRYPOINT`, no supervisor, no `CMD` other than the base image's, in `core/Dockerfile`.
- `core/Dockerfile` declares `VOLUME /var/lib/docker`.
- Base: `ubuntu:26.04` (codename `resolute`), pinned as `ubuntu:26.04@sha256:<digest>`.
- User: `dev`, uid 1000, gid 1000, home `/home/dev`, passwordless sudo, login shell `/usr/bin/fish`. The image's final `USER` is `dev`.
- `uv` and Bun arrive by `COPY --from=<image>:<version>@sha256:<digest>`, written as literal references because `COPY --from` cannot expand an `ARG`. Renovate's Dockerfile manager tracks them as written.
- Claude Code and OpenCode arrive by `bun install -g <pkg>@${<NAME>_VERSION}`, not by npm. Each version is an `ARG <NAME>_VERSION=<exact version>` line with a `# renovate: datasource=npm depName=<pkg>` comment directly above it.
- No per-file checksums.
- Image name: `ghcr.io/plume-works/core`. Tags: `edge` and the full commit SHA, and no others. Platforms: `linux/amd64`, `linux/arm64`.
- GitHub Actions are pinned by full commit SHA with a `# vX.Y.Z` trailing comment.
- The repo is `https://github.com/plume-works/images.git`. `main` holds one commit with an empty `README.md`; work on the branch that carries the design and this plan.

## Review Focus

- `start-dockerd` run when a daemon is already up: exits 0 and starts no second daemon. (Task 2 test)
- `start-dockerd` run in a container without privilege: exits non-zero within its timeout and prints the daemon log tail; it does not hang. (Task 2 test)
- Tools invoked by `dev` through a fish login shell, not only through `docker run core <tool>`: every tool resolves on `PATH`. (Task 1 test)
- `/home/dev` and everything under it owned by `dev:dev` after the base image's `ubuntu` user is replaced. (Task 1 test)
- `dev` runs `docker` without `sudo` once the daemon is up. (Task 2 test)

---

### Task 1: Core image with tools

**Files:**
- Create: `core/Dockerfile`
- Create: `core/test.sh`
- Create: `docker-bake.hcl`
- Create: `.dockerignore`

**Interfaces:**
- Produces: `docker buildx bake core` builds and loads `ghcr.io/plume-works/core:edge` for the host platform.
- Produces: `core/test.sh <image>`: runs every check against `<image>`, prints one `ok`/`FAIL` line per check, exits non-zero if any failed. Takes an optional second argument `tools` or `docker` to run one group; default is both. Task 2 adds the `docker` group.
- Produces: bake variables `REGISTRY` (default `ghcr.io/plume-works`) and `TAG` (default `edge`); target `core` with `context = "core"`.

- [ ] **Step 1: Write `core/test.sh` with the `tools` group**

POSIX `sh`, `set -eu`. A helper `check <description> <command...>` runs `docker run --rm "$image" <command...>`, prints `ok <description>` or `FAIL <description>`, and records failure. Checks, each as its own line:

```sh
check "git"            git --version
check "git-lfs"        git lfs version
check "gh"             gh --version
check "uv"             uv --version
check "uvx"            uvx --version
check "bun"            bun --version
check "claude"         claude --version
check "opencode"       opencode --version
check "gcc"            gcc --version
check "make"           make --version
check "curl"           curl --version
check "jq"             jq --version
check "rg"             rg --version
check "less"           less --version
check "docker cli"     docker --version
check "buildx"         docker buildx version
check "compose"        docker compose version
check "user is dev"    sh -c '[ "$(id -un)" = dev ] && [ "$(id -u)" = 1000 ] && [ "$(id -g)" = 1000 ]'
check "sudo"           sudo -n true
check "login shell"    sh -c '[ "$(getent passwd dev | cut -d: -f7)" = /usr/bin/fish ]'
check "home owned"     sh -c '[ -z "$(find /home/dev ! -user dev -o ! -group dev)" ]'
check "no entrypoint"  true   # replaced below
check "fish login PATH" fish -l -c 'for t in git gh uv bun claude opencode docker; command -q $t; or exit 1; end'
```

Replace the `no entrypoint` placeholder with a host-side check, outside the `check` helper: `docker inspect --format '{{json .Config.Entrypoint}}' "$image"` must print `null`.

- [ ] **Step 2: Write `docker-bake.hcl` and run the test to see it fail**

`variable "REGISTRY"`, `variable "TAG"`, `group "default" { targets = ["core"] }`, `target "core"` with `context = "core"`, `tags = ["${REGISTRY}/core:${TAG}"]`, `output = ["type=docker"]`.

Run: `docker buildx bake core`
Expected: FAIL, `core/Dockerfile` not found.

- [ ] **Step 3: Write `core/Dockerfile`**

Order, one concern per `RUN` so a version bump rebuilds from its own line down:

1. `FROM ubuntu:26.04@sha256:<digest>` (resolve the current digest with `docker buildx imagetools inspect ubuntu:26.04`).
2. `ARG DEBIAN_FRONTEND=noninteractive`; Ubuntu apt packages: `ca-certificates curl gnupg sudo git git-lfs build-essential jq ripgrep less fish procps` (`procps` supplies `pgrep`, which the Task 2 tests rely on). Clean `/var/lib/apt/lists` in the same layer, here and in every apt layer.
3. Vendor apt repositories, each with its key in `/etc/apt/keyrings`: GitHub CLI (`gh`) and Docker (`docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin`).
4. `COPY --from=ghcr.io/astral-sh/uv:<version>@sha256:<digest> /uv /uvx /usr/local/bin/`
5. `COPY --from=oven/bun:<version>@sha256:<digest> /usr/local/bin/bun /usr/local/bin/bun`, plus a `bunx` symlink to it.
6. `ARG CLAUDE_CODE_VERSION` / `ARG OPENCODE_VERSION` with renovate comments (`depName=@anthropic-ai/claude-code` and `depName=opencode-ai`), each followed by its own `bun install -g <pkg>@${...}`. Set these for the install `RUN` only, not as image `ENV`: `BUN_INSTALL_BIN=/usr/local/bin`, `BUN_INSTALL_GLOBAL_DIR=/usr/local/share/bun-global`, and `BUN_INSTALL_CACHE_DIR` pointing at a temporary directory removed in the same layer. Both packages place their binary from a postinstall script, which Bun runs for a global install.
7. User: the base image ships `ubuntu` at uid 1000. Rename it in place (`usermod -l dev -d /home/dev -m ubuntu`, `groupmod -n dev ubuntu`), set the shell to `/usr/bin/fish`, add `dev` to the `docker` group, write `/etc/sudoers.d/dev` with `dev ALL=(ALL) NOPASSWD:ALL` and mode `0440`.
8. `USER dev`, `WORKDIR /home/dev`.

All tools install to system paths (`/usr/bin`, `/usr/local/bin`), so no shell profile edits are needed for `PATH`.

- [ ] **Step 4: Write `.dockerignore`**

Contents: `.git`, `.DS_Store`.

- [ ] **Step 5: Build and run the test**

Run: `docker buildx bake core && core/test.sh ghcr.io/plume-works/core:edge tools`
Expected: every line `ok`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add core/Dockerfile core/test.sh docker-bake.hcl .dockerignore
git commit -m "Add core image with dev tools"
```

---

### Task 2: Opt-in Docker daemon

**Files:**
- Create: `core/start-dockerd`
- Modify: `core/Dockerfile` (one `COPY` line and `VOLUME /var/lib/docker`, both before `USER dev`)
- Modify: `core/test.sh` (add the `docker` group)

**Interfaces:**
- Consumes: `check` helper and group argument from Task 1.
- Produces: `/usr/local/bin/start-dockerd` in the image, mode `0755`, owned by root. Contract:
  - Re-executes itself under `sudo` when not root, passing `START_DOCKERD_TIMEOUT` through explicitly (`sudo` resets the environment).
  - If `docker info` already succeeds: exit 0, start nothing.
  - Otherwise starts `dockerd` in the background, output to `/var/log/dockerd.log`, and polls `docker info` once a second.
  - Timeout from `START_DOCKERD_TIMEOUT` seconds, default `30`. On timeout: print the last 20 lines of the log to stderr, exit 1.
  - Prints nothing on success.

- [ ] **Step 1: Add the `docker` group to `core/test.sh`**

These need their own `docker run` flags, so they do not use `check`'s plain form; add a variant that takes extra run flags.

```sh
# privileged: daemon comes up, dev can use it, second call is a no-op.
# No -v here: the image's own VOLUME must be what keeps /var/lib/docker off the overlay root.
check_run "dockerd starts"      --privileged -- sh -c 'start-dockerd && docker run --rm hello-world'
check_run "dev without sudo"    --privileged -- sh -c 'start-dockerd && docker info >/dev/null'
check_run "idempotent"          --privileged -- sh -c 'start-dockerd && start-dockerd && [ "$(pgrep -xc dockerd)" = 1 ]'
check_run "data on a volume"    -- sh -c 'grep -q " /var/lib/docker " /proc/mounts'
# unprivileged: the script's own timeout fires (exit 1, log tail on stderr); it does not hang.
# Exit 1 exactly: 127 would mean the script is missing, 124 that the outer timeout fired.
check_run "fails unprivileged"  -e START_DOCKERD_TIMEOUT=5 -- sh -c 'timeout 20 start-dockerd 2>/tmp/err; [ $? = 1 ] && [ -s /tmp/err ]'
# not started by default
check_run "inert by default"    -- sh -c '! pgrep -x dockerd'
```

- [ ] **Step 2: Run to verify it fails**

Run: `core/test.sh ghcr.io/plume-works/core:edge docker`
Expected: FAIL on every line except `inert by default`, which is `ok` (`start-dockerd: not found`, and no volume yet).

- [ ] **Step 3: Write `core/start-dockerd` to the contract above and add the `COPY --chmod=0755` and `VOLUME /var/lib/docker` lines to `core/Dockerfile`**

POSIX `sh`. No process supervision, no restart loop, no configuration file handling.

- [ ] **Step 4: Rebuild and run the whole test**

Run: `docker buildx bake core && core/test.sh ghcr.io/plume-works/core:edge`
Expected: every line `ok`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add core/start-dockerd core/Dockerfile core/test.sh
git commit -m "Add opt-in start-dockerd to core image"
```

---

### Task 3: Build and publish workflow

**Files:**
- Create: `.github/workflows/build.yml`

**Interfaces:**
- Consumes: `docker buildx bake core` with `REGISTRY`/`TAG`; `core/test.sh <image>`.
- Produces: on pull requests, a required check per architecture. On pushes to `main`, `ghcr.io/plume-works/core:edge` and `:<sha>` as multi-arch manifests.

- [ ] **Step 1: Write the workflow**

- Triggers: `pull_request`, `push` to `main`, `workflow_dispatch`.
- Top-level `permissions: contents: read`. Concurrency group per ref, cancelling in-progress runs on pull requests only.
- Job `build`: matrix of `{arch: amd64, runner: ubuntu-24.04}` and `{arch: arm64, runner: ubuntu-24.04-arm}`. Steps: checkout, set up Buildx, `docker buildx bake core`, `core/test.sh ghcr.io/plume-works/core:edge`. This job needs `packages: write`.
- On `main` only, the `build` job then logs in to GHCR with `GITHUB_TOKEN` and pushes the tested build by digest, with no tag, so no per-architecture tag is ever published:

  ```bash
  docker buildx bake core \
    --set core.tags=ghcr.io/plume-works/core \
    --set 'core.output=type=image,push-by-digest=true,name-canonical=true,push=true' \
    --metadata-file meta.json
  ```

  This second bake is served from the first one's build cache. The digest is `.core["containerimage.digest"]` in `meta.json`; upload it as an artifact named `digest-<arch>`.
- Job `manifest`: `main` only, needs `build`, `packages: write`. Downloads both digest artifacts and runs `docker buildx imagetools create -t ghcr.io/plume-works/core:edge -t ghcr.io/plume-works/core:<sha> ghcr.io/plume-works/core@<amd64 digest> ghcr.io/plume-works/core@<arm64 digest>`.
- `edge` therefore moves only after both architectures pass `core/test.sh`.
- Pin every action by commit SHA with a version comment.

- [ ] **Step 2: Validate locally**

Run: `docker run --rm -v "$PWD":/repo -w /repo rhysd/actionlint:latest`
Expected: no output, exit 0.

- [ ] **Step 3: Commit, push the branch, open a pull request, and confirm both `build` jobs pass**

```bash
git add .github/workflows/build.yml
git commit -m "Add build and publish workflow"
```

Pushing and opening the pull request are outward-facing: confirm with the user first.

- [ ] **Step 4: After the user merges the pull request, verify the publish path**

The login, push and `manifest` job run only on `main`, so this is their first run.

Run: `docker buildx imagetools inspect ghcr.io/plume-works/core:edge`
Expected: platforms `linux/amd64` and `linux/arm64`.

Run: `docker buildx imagetools inspect ghcr.io/plume-works/core:<merge commit sha>`
Expected: the same digest as `edge`.

Run: `core/test.sh ghcr.io/plume-works/core:edge`
Expected: every line `ok`, exit 0.

---

### Task 4: Renovate and README

**Files:**
- Create: `.github/renovate.json`
- Modify: `README.md` (exists, empty)

**Interfaces:**
- Consumes: the `# renovate:` comments and digest pins from Task 1; SHA-pinned actions from Task 3.

- [ ] **Step 1: Write `.github/renovate.json`**

- `extends`: `config:recommended`, `docker:pinDigests`, `helpers:pinGitHubActionDigests`, `customManagers:dockerfileVersions`.
- Top-level `minimumReleaseAge: "3 days"`, applying to every update.
- One package rule enabling `automerge` with `automergeType: "pr"` and `platformAutomerge: true` for all updates.
- One package rule, placed after it, with `matchDepNames: ["ubuntu"]` and `matchUpdateTypes: ["major", "minor"]` set to `enabled: false`, so only the `26.04` digest moves.

- [ ] **Step 2: Validate the config and confirm it sees every pin**

Run: `docker run --rm -v "$PWD":/repo -w /repo renovate/renovate renovate-config-validator .github/renovate.json`
Expected: `Config validated successfully`.

Run: `docker run --rm -v "$PWD":/repo -w /repo -e LOG_LEVEL=debug renovate/renovate --platform=local --dry-run=lookup`
Expected: the log lists `ubuntu`, `ghcr.io/astral-sh/uv`, `oven/bun`, `@anthropic-ai/claude-code`, `opencode-ai`, and each action in `build.yml` as detected dependencies. A pin missing from that list is a failure of this step.

In the same log, find how the 3-day wait is applied to the `ubuntu`, `uv` and Bun digest updates, where Renovate may have no release timestamp. If such an update would skip the wait, or would never become mergeable, report that to the user; do not change the config to work around it.

- [ ] **Step 3: Write `README.md`**

Keep it short: what the repo is (one paragraph), the image table with pull names, how to build and test locally (`docker buildx bake core`, `core/test.sh <image>`), how a consumer starts Docker (`start-dockerd`, needs privileged or sysbox; every container gets an anonymous volume at `/var/lib/docker`), and a link to `docs/superpowers/specs/2026-11-17-core-image-design.md`. Do not restate the design.

- [ ] **Step 4: Commit**

```bash
git add .github/renovate.json README.md
git commit -m "Add Renovate config and README"
```

- [ ] **Step 5: Hand the user the one-time settings only they can change**

Install the Renovate GitHub app on the repo; enable "Allow auto-merge"; require the two `build` checks on `main`; set the `core` package's visibility after the first publish.

---

## Handoff notes (2026-11-17)

**Environment prerequisite:** every verification step needs a working Docker daemon, and Task 2 needs `--privileged`. The devcontainer this plan was written in has no Docker and is not privileged. Run the plan somewhere that has both.

**Pins resolved on 2026-11-17** (use these, or re-resolve if stale):

| Pin | Value |
|---|---|
| `ubuntu:26.04` | `sha256:d66b366dac61b575bee2aef07e9c26e8070096fbe84a3d4d3eb0da069b5d76db` |
| `ghcr.io/astral-sh/uv:0.13.8` | `sha256:5cc1805e2426484abca4ad46ea783bab281fdb225fd82d8ce6d66a81254bac85` |
| `oven/bun:1.4.4` | `sha256:1d22548f177f4ff38e0c15baa3c2c46c6c2060ba2d1bc573bb4720b407548f1d` |
| `@anthropic-ai/claude-code` | `2.1.326` |
| `opencode-ai` | `1.19.6` |

Confirmed with Bun 1.4.4 on `linux/arm64`: `bun install -g` of both packages at the versions above, with `BUN_INSTALL_BIN` and `BUN_INSTALL_GLOBAL_DIR` set, gives a working `claude --version` and `opencode --version` on a machine with no Node installed. Not tried on `linux/amd64`.

The repo is public (checked 2026-11-17), so the `ubuntu-24.04-arm` runner in Task 3 is free to use.

Confirmed reachable: Docker's apt suite `resolute` and the GitHub CLI apt repo (`stable`).
