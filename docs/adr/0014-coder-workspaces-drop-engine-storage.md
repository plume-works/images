# Coder workspaces do not keep the Docker engine's storage

A Coder workspace keeps only its home directory. The inner Docker engine's storage (`/var/lib/docker` and
`/var/lib/containerd`) gets fresh anonymous volumes from the image's declared volumes (ADR 0004) with every workspace
container, and they are removed with it.

Every start, stop and template update replaces the workspace container. Under sysbox, the old container can still
hold its mounts of a named volume when its replacement mounts the same volume; sysbox-mgr then logs that the volume
"should be mounted in one container only, but is already mounted in containers [...]": two Docker engines on one
storage directory, which sysbox does not support. On our sysbox host running Coder (Sysbox CE 0.7.1, the latest
release) these warnings came with stale, overlapping sysbox and OverlayFS mounts, and the host went down.

## Consequences

- A restart or template update loses the inner engine's images, containers, volumes and build cache; they are
  pulled or built again. Data that must survive belongs in home.
- The first build of an existing workspace after this change deletes its old engine volumes, with their data. If
  sysbox still holds their mounts, that build fails on removing them; restart sysbox or remove the volumes by hand
  once the old container is gone, then build again.
- An anonymous volume outlives its container only if the container is removed some other way than by Coder;
  `docker volume prune` on the host clears it.

## Considered options

- **Named volumes for the engine's storage, reused by every container of a workspace** (the template before this
  decision): the cause above.
- **A unique named volume per container, deleted once the old container and its mounts are gone**: keeps the cache,
  but needs a collector that can tell when sysbox has let go of a volume. Not worth it for a cache.
