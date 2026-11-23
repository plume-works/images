# Core systemd image

`ghcr.io/plume-works/core-systemd`: the core image with systemd as PID 1 and the Docker engine run as a service.
It is the parent of the [Coder template image](coder-template.md) and the
[devcontainer base image](devcontainer-base.md); build on it with `FROM`, and to work in it use one of those two.

Run it with its own entrypoint under sysbox, with nothing mounted at the inner engine's storage, or in privileged
mode, with volumes there ([ADR 0014](../adr/0014-no-engine-storage-volumes.md)):

```sh
docker run -d --runtime=sysbox-runc ghcr.io/plume-works/core-systemd:edge@sha256:<digest>
docker run -d --privileged -v /var/lib/docker -v /var/lib/containerd ghcr.io/plume-works/core-systemd:edge@sha256:<digest>
```

- The default user is root. `dev`'s systemd user manager runs from boot, without a login.
- Logs for every unit are in the journal (`journalctl`); it does not hold the kernel log.
- Nothing updates itself.
- Once a day the inner engine is cleaned up ([ADR 0023](../adr/0023-daily-cleanup-of-the-inner-engine.md)). Each
  kind has its own setting, an age (Go duration: `30m`, `168h`) or `off`:

  | Setting | Default | Removes |
  | --- | --- | --- |
  | `PRUNE_STOPPED_CONTAINERS` | `168h` | containers stopped longer ago than the age |
  | `PRUNE_ANONYMOUS_VOLUMES` | `168h` | anonymous volumes no container uses, created longer ago than the age |
  | `PRUNE_NAMED_VOLUMES` | `off` | named volumes no container uses, created longer ago than the age |
  | `PRUNE_IMAGES` | `168h` | images no container uses, pulled or built longer ago than the age |
  | `PRUNE_BUILD_CACHE` | `168h` | build cache unused for the age |

  Docker keeps no last-use time for images or volumes, so one whose containers were all removed (say, run with
  `--rm`) goes once it is older than the age, and an image is pulled again on next use. Change a setting with a
  drop-in, in the image that builds on this one or at run time:

  ```ini
  # /etc/systemd/system/docker-prune.service.d/settings.conf
  [Service]
  Environment=PRUNE_STOPPED_CONTAINERS=720h
  Environment=PRUNE_NAMED_VOLUMES=168h
  ```

  The schedule is `docker-prune.timer`'s; change it with a drop-in there.
- Stop it with more than the default 10 seconds (`docker stop -t 60`), so the inner engine can stop its own
  containers.
