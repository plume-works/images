# Images

Container images published by plume-works for running and developing software with coding agents.
See [GLOSSARY.md](GLOSSARY.md) for the vocabulary and [docs/adr/](docs/adr/) for the decisions behind them.

This repository publishes four images and nothing else. Each is built on the one before it, from the same
commit, so CI, workspaces and dev containers always have the same toolchain.

| Image | Who it is for | Usage |
|---|---|---|
| Core image `ghcr.io/plume-works/core` | CI authors | [docs/usage/core.md](docs/usage/core.md) |
| Core systemd image `ghcr.io/plume-works/core-systemd` | Builders of the two images below | [docs/usage/core-systemd.md](docs/usage/core-systemd.md) |
| Coder template image `ghcr.io/plume-works/coder-template` | Coder host administrators (and, through its template, workspace users) | [docs/usage/coder-template.md](docs/usage/coder-template.md) |
| Devcontainer base image `ghcr.io/plume-works/devcontainer-base` | Developers using a dev container from local VS Code | [docs/usage/devcontainer-base.md](docs/usage/devcontainer-base.md) |

All four are published for `linux/amd64` and `linux/arm64`. The only tags are `edge` (the latest tested `main`;
it moves on all four images together, and only when every image passes on both architectures) and `pr-N` (a pull
request, deleted two weeks after it closes). There are no version tags: pin by tag and digest,
`<image>:edge@sha256:<digest>`, and let Renovate propose digest bumps. The `cache-amd64` and `cache-arm64` tags are CI's
build cache, not images to pull.

**Not a goal for now:** an image deployed as a service that takes coding requests from agents. It is a known
future image, but the four images above should not grow features in anticipation of it.

**Admission rule for the core image:** a build toolchain is added only when at least two plume-works repositories
need it in CI. Interactive conveniences are added at the maintainer's discretion. Anything else belongs in the
repository that needs it, in its `mise.toml`.

## Developing this repository

This repository is developed inside its own devcontainer base image (`.devcontainer.json`, privileged-mode
snippet), so the image gets continuous real use and its engine builds and tests the images.

It takes no outside contributions: pull requests come from collaborators' branches of this repository, and forks
are not supported ([ADR 0020](docs/adr/0020-pull-requests-from-collaborators-only.md)).

Each image lives in `images/<name>/` with its `Dockerfile` and `smoke.sh`; `images/docker-bake.hcl` lists them, and
`.github/workflows/images.yml` builds, tests and publishes them all.

### Building and testing

```sh
(cd images && docker buildx bake)
images/core/smoke.sh ghcr.io/plume-works/core:ci
images/core-systemd/smoke.sh ghcr.io/plume-works/core-systemd:ci
images/coder-template/smoke.sh ghcr.io/plume-works/coder-template:ci
images/devcontainer-base/smoke.sh ghcr.io/plume-works/devcontainer-base:ci
```

The devcontainer base image's smoke test brings the image up from the privileged-mode snippet in
[docs/usage/devcontainer-base.md](docs/usage/devcontainer-base.md), so that snippet is tested documentation.

**The Coder template needs a manual check** before merging a change to it or its image, because CI has neither
Coder nor sysbox. Push the template under a scratch name, create a workspace from a repository you can push to,
and check:

1. The build log shows the container created with runtime `sysbox-runc`; the agent connects, and the startup
   script finishes. `systemctl --user status agent-services.target opencode claude-remote-control` shows the
   target active.
2. A secret reaches a service: define a Coder secret (say `PROBE_SECRET`), restart the workspace, and
   `systemctl --user show-environment | grep PROBE_SECRET` and
   `tr '\0' '\n' < /proc/$(systemctl --user show -p MainPID --value opencode)/environ | grep PROBE_SECRET` both
   find it.
3. `git commit` shows your Coder full name (or your username, if the account has no full name) and email;
   `git push` works with only the `GITHUB_TOKEN` secret.
4. A killed service restarts: `systemctl --user kill -s KILL opencode`, then within seconds it is active again
   with a new PID, `tmux -L opencode attach -r` shows the server, and the OpenCode button works (after
   `OPENCODE_PASSWORD`).
5. VS Code Desktop and code-server open the repository.
6. Home survives a rebuild: write a file in `~`, stop and start the workspace (or update it to a new template
   version), and the file is still there, while a `docker pull`ed image is gone
   ([ADR 0014](docs/adr/0014-no-engine-storage-volumes.md)).
7. Stopping the workspace finishes within the 60-second grace period, without Docker killing the container.

### Linting

[pre-commit](https://pre-commit.com/) runs every linter, hadolint, shellcheck, actionlint, ruff and Terraform
`fmt`/`validate` among them, from `.pre-commit-config.yaml`; `.github/workflows/lint.yml` runs it on every pull request,
and any finding fails it. The Python-packaged tools are pinned in `uv.lock`, the Terraform image in
`.pre-commit-config.yaml`. The dev container installs the git hooks; elsewhere, or to run them all by hand:

```sh
uv run pre-commit install
uv run pre-commit run --all-files
```

### How versions are updated

Everything is pinned, and a pin changes only through a pull request that passes the same build, test and `pr-N`
publish as any other, opened by [Renovate](https://docs.renovatebot.com/) ([`renovate.json`](renovate.json)).
Apt packages come from a dated snapshot of the Ubuntu archive ([ADR 0022](docs/adr/0022-all-inputs-are-pinned.md)).

To pin a new tool in a Dockerfile, put an `ARG <NAME>_VERSION` (a plain `<NAME>_VERSION=` in a `smoke.sh`)
directly below a `# renovate:` comment, with no `v` prefix on the value:

```dockerfile
# renovate: datasource=github-releases depName=cli/cli extractVersion=^v(?<version>.+)$
ARG GH_VERSION=2.105.0
```
