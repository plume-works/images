# No volumes at the Docker engine's storage under sysbox

Supersedes [ADR 0004](0004-engine-storage-declared-as-volumes.md).

The core image declares no volumes. Under sysbox, nothing is mounted at the inner Docker engine's storage
(`/var/lib/docker`, `/var/lib/containerd`): sysbox gives each container its own host directories there, created
and removed with the container. So a Coder workspace keeps only its home directory, and the devcontainer sysbox
snippet mounts only home. In privileged mode, which has no such storage, the consumer mounts volumes there: a CI
job container one at `/var/lib/docker`, a container running systemd one at each path.

A volume there under sysbox is fatal. Every start, stop and template update replaces a Coder workspace container,
and the old container can still hold its mounts of a volume when its replacement mounts the same one; sysbox-mgr
then logs that the volume "should be mounted in one container only, but is already mounted in containers [...]".
On our sysbox host running Coder (Sysbox CE 0.7.1, the latest release) this came with stale, overlapping sysbox and
OverlayFS mounts, and the host went down.

## Consequences

- Under sysbox, a restart, rebuild or template update loses the inner engine's images, containers, volumes and
  build cache; they are pulled or built again. Data that must survive belongs in home.
- Privileged consumers (CI jobs, the smoke tests, the devcontainer privileged snippet) carry volume flags.
  `start-docker` refuses to start with its storage on the overlay filesystem and says what to mount.

## Considered options

- **Volumes declared in the core image** (ADR 0004): every consumer worked with no flags, but under sysbox the
  declared volumes are mounts at the engine's storage, and named volumes over them were reused across containers.
- **Named volumes per workspace, reused by every container** (the Coder template and devcontainer sysbox snippet
  before this decision): the cause above.
- **A unique named volume per container, deleted once the old container and its mounts are gone**: keeps the cache,
  but needs a collector that can tell when sysbox has let go of a volume. Not worth it for a cache.
