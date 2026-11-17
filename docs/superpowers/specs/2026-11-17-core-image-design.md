# Core image design

A clean restart of `plume-works/agent-devcontainer` as a small family of
container images. This document covers the first one, `core`.

Lines marked *(Claude's call)* were proposed by Claude and not objected to. They
are defaults, open to change.

## Images wanted

1. A devcontainer that works in VS Code.
2. A Coder workspace image, run directly, not nested.
3. Far goal: an image deployed as a service that takes coding requests from
   agents.

The devcontainer is not built first; starting there is how the old repo went
wrong. The order of the three after `core` is not decided.

## Approach

A shared `core` image holds the tools. Each image above is a layer on top of it.

One directory per image, wired by a bake file, so a consumer sees only the
finished core image.

```
core/Dockerfile
core/start-dockerd
core/test.sh
docker-bake.hcl
.github/workflows/build.yml
.github/renovate.json
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
| npm, exact versions | Claude Code, OpenCode | npm registry integrity |

No per-file checksum pins: the old repo had them only for tools downloaded
straight from GitHub releases, and none of those remain.

**Docker daemon:** the engine is installed and `core/start-dockerd` starts it.
Nothing calls the script by default; a consumer calls it from its own startup
and must run privileged or under sysbox. Not chosen: binaries only (each
consumer rewrites daemon startup), and an entrypoint in the core that starts the
daemon (every consumer inherits it and must run privileged).

It follows that `core` has no entrypoint or supervisor.

**User** *(Claude's call)*: one non-root user `dev` (uid 1000, passwordless
sudo, fish as login shell), shared by consumers.

## Build and publish *(Claude's call)*

- `ghcr.io/plume-works/core`, tagged `edge` and by commit SHA, on pushes to
  main, for `linux/amd64` and `linux/arm64`.
- `core/test.sh` runs each tool's version command in the built image, then
  starts the daemon in a privileged run and runs `hello-world`. CI runs it on
  both architectures before publishing.

## Upkeep

Renovate, as the old repo had. *(Claude's call for the rest:)* the hosted
Renovate app, with no workflow or script in the repo. It tracks the base image
digest, the pinned tool versions and the workflow's actions, and automerges
when the build passes. Ubuntu release changes are left as a manual decision.
