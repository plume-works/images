# Core systemd image

`ghcr.io/plume-works/core-systemd`: the core image with systemd as PID 1 and the Docker engine run as a service.
It is the parent of the [Coder template image](coder-template.md) and the
[devcontainer base image](devcontainer-base.md); build on it with `FROM`, and to work in it use one of those two.

Run it with its own entrypoint under sysbox, with nothing mounted at the inner engine's storage, or in privileged
mode, with volumes there ([ADR 0013](../adr/0013-no-engine-storage-volumes.md)):

```sh
docker run -d --runtime=sysbox-runc ghcr.io/plume-works/core-systemd:edge@sha256:<digest>
docker run -d --privileged -v /var/lib/docker -v /var/lib/containerd ghcr.io/plume-works/core-systemd:edge@sha256:<digest>
```

- The default user is root. `dev`'s systemd user manager runs from boot, without a login.
- Logs for every unit are in the journal (`journalctl`); it does not hold the kernel log.
- Nothing updates itself.
- Once a week, unused Docker images pulled or built more than a week ago, and build cache unused for a week, are
  removed. Docker keeps no last-use time for images, so an image whose containers were all removed (say, run with
  `--rm`) goes once it is a week old and is pulled again on next use. Volumes and containers, stopped ones
  included, are never removed.
- Stop it with more than the default 10 seconds (`docker stop -t 60`), so the inner engine can stop its own
  containers.
