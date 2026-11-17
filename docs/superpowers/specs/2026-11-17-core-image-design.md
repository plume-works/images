# Core image design

This repo builds a small family of container images for agent-driven development.
It is a clean restart of `plume-works/agent-devcontainer`.

This is the design for step 1, the core image, and for the shape of the image
family. Each later image gets its own design and plan under `docs/superpowers/`.

## Rules

- The repo holds images only: Dockerfiles, a bake file, a build workflow, Renovate
  config, a README, and one design plus one plan per step under
  `docs/superpowers/`. No knowledge bases, plugin catalogs or other agent
  workflow scaffolding.
- The core image has no entrypoint, no supervisor, and nothing that exists for
  one host. `docker run core` is inert.
- Consumers build `FROM` the finished core. They never push requirements down
  into it.

## Images

| Image | Status | Purpose |
|---|---|---|
| `core` | step 1 | Tools only. Host-neutral. |
| `coder` | next | Image a Coder workspace runs directly. |
| `devcontainer` | later | VS Code Dev Container. |
| factory | far goal | Service that takes coding requests from agents. |

The devcontainer deliberately does not come first. In the old repo it did, and
its assumptions became the foundation everything else had to work around.

## Layout

One directory per image, wired by a bake file, so each consumer can only see the
finished core image. A new image or optional layer (for example `desktop`) is a
new directory.

```
core/Dockerfile
core/start-dockerd
core/test.sh
docker-bake.hcl
.github/workflows/build.yml
.github/renovate.json
```

Rejected:

- **One multi-stage Dockerfile.** Simplest, but nothing separates core from
  consumers and the file grows with every image.
- **Devcontainer Features.** Ties every image to a devcontainer builder, which is
  the nesting this restart removes.
- **Ansible.** Poor layer caching and a lot of surface for an images-only repo.
  Revisit if the same definitions must provision non-container machines.

## Core contents

| Source | Tools | Integrity |
|---|---|---|
| Ubuntu 26.04 base | | tag and digest |
| Ubuntu apt | git, git-lfs, build-essential, curl, jq, ripgrep, less, fish | apt signatures |
| Vendor apt repositories | Docker CE with Buildx and Compose, `gh`, Node 24 | apt signatures |
| Official images, by digest | `uv`, Bun (standard build) | image digest |
| npm, exact versions | Claude Code, OpenCode | npm registry integrity |

No per-file checksum pins. The old repo needed them only for direct GitHub
release downloads, and those are gone.

**User:** one non-root user `dev` (uid 1000, passwordless sudo, fish as login
shell), shared by every consumer.

**Docker daemon:** the engine is installed and `core/start-dockerd` starts it.
Nothing calls the script by default. A consumer calls it from its own startup
hook and must run privileged or under sysbox. Rejected: binaries only (each
consumer rewrites daemon startup) and an entrypoint in the core (every consumer
inherits it and must run privileged).

## Build and publish

- `ghcr.io/plume-works/core`, tagged `edge` and by commit SHA, on pushes to
  main, for `linux/amd64` and `linux/arm64`.
- CI check: run each tool's version command in the built image, then start the
  daemon in a privileged run and run `hello-world`.

## Upkeep

The hosted Renovate app, with no workflow or script in the repo. It tracks the
base image digest, tool versions (build arguments in `core/Dockerfile` with a
`# renovate:` comment) and the workflow's actions (pinned by commit SHA). Bumps
automerge when the build passes. Ubuntu release changes are excluded and stay a
manual decision.
