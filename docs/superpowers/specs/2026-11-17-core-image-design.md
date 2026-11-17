# Core image design

A clean restart of `plume-works/agent-devcontainer` as a small family of
container images. This document covers the first one, `core`.

Lines marked *(Claude's call)* were proposed by Claude and not objected to. They
are defaults, open to change.

## Why

In Anton's words:

- The old repo "became bloatware".
- "The biggest issue of old repo was use of half baked skills (iwe* workflow)
  that did poor job in slopification of the repo."
- This is "a restart from clean slate", to be kept "clean and composable to an
  extent".

## Images wanted

1. A devcontainer that works in VS Code.
2. A Coder workspace image, run directly, not nested.
3. Far goal: an image deployed as a service that takes coding requests from
   agents.

The devcontainer is not built first; starting there is how the old repo went
wrong. The order of the three after `core` is not decided.

## This step

**Delivers:** the repo layout, a published `core` image, and automated upkeep.

**Must not happen:** the core gains an entrypoint, a supervisor, or anything
that exists for one host.

**Not in this step** *(Claude's call)*: any image built on `core`, the old
repo's Xpra desktop, keyring, firewall and runtime package, and Ansible.

## Approach

A shared `core` image holds the tools. Each image above is a layer on top of it.

One directory per image, wired by a bake file. Each later image can only see
the finished core image, so it cannot push its requirements down into the core,
and a new image is a new directory with no edits to existing ones. The cost is
a few more files, and a bake file to make local builds use the freshly built
core.

```
core/Dockerfile
core/start-dockerd
core/test.sh
docker-bake.hcl
.dockerignore
.github/workflows/build.yml
.github/renovate.json
README.md
```

Considered and not chosen:

- **One multi-stage Dockerfile.** Simplest, but nothing separates core from
  consumers.
- **Devcontainer Features.** Would put a devcontainer builder under every image.
- **Ansible.** Starting simple with plain Dockerfiles; can move to Ansible if
  the need arises.

## Core contents

| Source | Tools | Integrity |
|---|---|---|
| Ubuntu 26.04 base | | tag and digest |
| Ubuntu apt | git, git-lfs, build-essential, curl, jq, ripgrep, less, fish | apt signatures |
| Vendor apt repositories | Docker CE with Buildx and Compose, `gh`, Node 24 | apt signatures |
| Official images, by digest | `uv`, Bun | image digest |
| npm registry, installed with Bun, exact versions | Claude Code, OpenCode | exact version only; no hash is stored in this repo |

No per-file checksum pins: the old repo had them only for tools downloaded
straight from GitHub releases, and none of those remain.

Claude Code and OpenCode stay at an exact version with no stored hash, and are
installed with Bun, not npm (Anton's decisions). Not chosen: a lockfile
installed with `npm ci`, which would store hashes at the cost of two more files
and a non-global install.

Apt packages are not version-pinned *(Claude's call)*. They take whatever
version is current when the image is rebuilt, and Renovate does not track them.

`procps` is also installed *(Claude's call)*, because `core/test.sh` uses
`pgrep`.

**Docker daemon:** the engine is installed and `core/start-dockerd` starts it.
Nothing calls the script by default; a consumer calls it from its own startup
and must run privileged or under sysbox. Not chosen: binaries only (each
consumer rewrites daemon startup), and an entrypoint in the core that starts the
daemon (every consumer inherits it and must run privileged).

`core` declares `/var/lib/docker` as a volume, as the official Docker-in-Docker
image does, so the nested daemon's data is never on the container's overlay
filesystem (Anton's decision). The cost: every container made from `core` or a
consumer gets an anonymous volume there, whether or not it starts Docker. Not
chosen: measuring first whether the volume is needed, and only documenting that
consumers should mount one.

**User** *(Claude's call)*: one non-root user `dev` (uid and gid 1000, home
`/home/dev`, passwordless sudo, fish as login shell), shared by consumers.

## Build and publish *(Claude's call)*

- `ghcr.io/plume-works/core`, tagged `edge` and by commit SHA, on pushes to
  main, for `linux/amd64` and `linux/arm64`.
- `core/test.sh` runs each tool's version command in the built image, then
  starts the daemon in a privileged run and runs `hello-world`. CI runs it on
  both architectures before publishing.

## Upkeep

Renovate, as the old repo had. *(Claude's call for the rest:)*

- The hosted Renovate app, with no workflow or script in the repo.
- It tracks the base image digest, the `uv` and Bun image versions and digests,
  the Claude Code and OpenCode versions, and the workflow's actions.
- Claude Code and OpenCode versions are `ARG` lines in `core/Dockerfile` with a
  `# renovate:` comment above each. Workflow actions are pinned by commit SHA.
- Updates automerge when the build passes.
- Every update waits until its release is 3 days old before it merges (Anton's
  decision, for all updates and not only the npm tools). Renovate may have no
  publish date for an image digest; the plan checks how it treats those.
- The base digest update doubles as the regular clean rebuild, which is
  when apt packages move.
- Ubuntu release changes are left as a manual decision.

## Left to the builder

Layer ordering and the internals of `start-dockerd`.

## Open questions

Raised in review on 2026-11-17 and not decided. The plan proceeds without them.

- **Decisions that outlive this image.** The shared `dev` user and the
  no-entrypoint rule bind every later image, but are recorded only in this
  document.
