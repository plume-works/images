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

## Building and testing locally

```sh
docker buildx bake --load
images/core/smoke.sh ghcr.io/plume-works/core:ci
```

Each image lives in `images/<name>/` with its `Dockerfile` and `smoke.sh`; `docker-bake.hcl` lists them, and
`.github/workflows/images.yml` builds, tests and publishes them all.
