# Docker engine in every image, run by systemd

Agents need a Docker engine they fully control, so every image here ships one. The Coder template image and the devcontainer base image run systemd as PID 1 with the Docker service enabled. The core image carries the same engine plus a small script that starts it on demand, because CI job containers do not own PID 1 and cannot run systemd.

Everything about booting under systemd lives once, in the core systemd image, which both of those images are built on.

supervisord, and any custom supervisor, is ruled out. In the predecessor repository (`plume-works/agent-devcontainer`) supervising the nested engine grew into a Python runtime package running as PID 1, and that package was a large share of what made that repository unmaintainable. systemd is maintained by someone else and already knows how to run Docker.

systemd in a container needs either the sysbox runtime or privileged mode:

- **Coder template**: sysbox is required, with no privileged fallback. The Coder host is a Linux server set up once, and a shared host is where privileged containers do the most damage.
- **Devcontainer base image**: the image does not choose. Docker Desktop on macOS offers sysbox only in a paid tier, while on Linux it is a free install, so each consumer sets sysbox or privileged mode in their own `devcontainer.json`. The image's metadata carries only what both options need.

## Considered options

- **Docker CLI only, engine supplied by each environment** (runner socket, docker-in-docker Feature). Rejected: the engine is a fundamental agent tool and must behave the same in all three images.
- **supervisord as PID 1.** Rejected for the reason above.
- **Privileged mode everywhere.** Rejected for Coder on safety grounds.
- **Sysbox everywhere.** Rejected because it shuts out macOS users without a paid Docker Desktop tier.
