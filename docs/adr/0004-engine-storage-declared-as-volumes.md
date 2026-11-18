# Docker engine storage declared as volumes in the core image

The Docker engine cannot start containers when its storage sits on the container's own overlay filesystem. The core image therefore declares `VOLUME ["/var/lib/docker", "/var/lib/containerd"]`, so the engine works with no volume flags: a CI job container needs only `--privileged`, and the systemd images need nothing beyond sysbox or privileged mode. `/var/lib/docker` is where the engine keeps everything when `start-docker` runs it without systemd; `/var/lib/containerd` is where `containerd.service` keeps its data under systemd, and the engine fails there without a volume of its own.

The alternative, leaving the volumes to every consumer, made the engine fail out of the box in all four images, with every CI job, `docker run` and template having to remember the same flags.

## Consequences

- The declaration is inherited by every image built on the core image, and a child image cannot undo it.
- Each container without a named volume there gets anonymous volumes, which `docker rm` without `-v` (a container run without `--rm`, a dev container rebuild) leaves behind. Where the engine's images and cache should persist, consumers still mount named volumes (the devcontainer snippets, the Coder template).
- A child image's build steps cannot write under `/var/lib/docker` or `/var/lib/containerd`: Docker discards writes to a declared volume during a build.
- Runtimes that ignore image volumes (Kubernetes) still put the storage on the overlay filesystem. `start-docker` keeps its check for that and refuses to start the engine there, saying what to mount; the core image's smoke test exercises it by unmounting the volume.
