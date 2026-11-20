# Devcontainer base image

`ghcr.io/plume-works/devcontainer-base`, for a dev container opened from local VS Code: the core systemd image
with `dev` as the remote user and the Claude Code VS Code extension. Inside you get systemd, a Docker engine run as
a service, and every tool and agent of the [core image](core.md).

Name it in the `image` field of your `devcontainer.json`, pinned by tag and digest, and use one of the two
snippets below; the image does not choose how it runs ([ADR 0001](../adr/0001-docker-engine-under-systemd.md)):

- **sysbox** (Linux hosts with [sysbox](https://github.com/nestybox/sysbox) installed): no privileged container.
- **Privileged mode** (macOS, or Linux without sysbox): Docker Desktop on macOS offers sysbox only in a paid tier.

Both mount a named volume for all of `/home/dev`, so agent sign-ins and shell history survive a rebuild. The home
volume is yours to keep, drop or replace; a new one is filled from the image's `/home/dev`. Under sysbox, mount
nothing at the Docker engine's storage: sysbox gives each container its own, and a volume there can take the
host down ([ADR 0014](../adr/0014-no-engine-storage-volumes.md)), so images and build cache go with each rebuild. In
privileged mode the engine needs volumes there; named ones keep its images and build cache across rebuilds.

With sysbox:

```jsonc
{
  "image": "ghcr.io/plume-works/devcontainer-base:edge@sha256:<digest>",
  "runArgs": ["--runtime=sysbox-runc"],
  "mounts": ["source=dc-${devcontainerId}-home,target=/home/dev,type=volume"]
}
```

In privileged mode (the smoke test brings this one up):

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
Docker volumes between two containers.

## Adding your own tooling

Use Features or your own Dockerfile on top. Things to know:

- **Do not add the `docker-in-docker` Feature** (nor `docker-outside-of-docker`): the image already runs an
  engine, and a second one, or the host's socket, would fight it over `/var/run/docker.sock` and its storage.
- Avoid Features whose entrypoint starts a daemon (`sshd`, say): it clashes with systemd. Features that only
  install something work.
- On a Linux host whose user is not UID 1000, the devcontainer CLI changes `dev`'s UID to match. Files in a home
  volume created before that keep UID 1000.
- **Not supported:** GitHub Codespaces, and nesting this dev container inside a Coder workspace (use the
  [Coder template image](coder-template.md) there). It is meant for local VS Code.
