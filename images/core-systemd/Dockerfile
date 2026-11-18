# Core systemd image: the core image with systemd as PID 1 and the Docker engine run as a service.
# Everything about booting lives here, once (ADR 0001). The default user stays root (no USER line),
# because systemd must run as root.
ARG BASE_IMAGE=core
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# systemd as init, with the D-Bus pieces a per-user manager needs. apt packages float.
# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get install -y --no-install-recommends systemd systemd-sysv dbus dbus-user-session libpam-systemd \
 && rm -rf /var/lib/apt/lists/*

# Units that cannot work in a container: kernel module loading, kernel debug and config mounts
# (they cannot mount under sysbox), binfmt, and consoles (under privileged mode getty finds the
# host's ttys and restart-loops into a failed state).
RUN systemctl mask \
      systemd-modules-load.service \
      sys-kernel-debug.mount sys-kernel-tracing.mount sys-kernel-config.mount \
      sys-fs-fuse-connections.mount \
      proc-sys-fs-binfmt_misc.automount proc-sys-fs-binfmt_misc.mount systemd-binfmt.service \
      getty.target console-getty.service \
      e2scrub_all.timer fstrim.timer

# Nothing updates itself: the operating system's periodic update timers are masked (not just
# disabled, so a package upgrade cannot re-enable them), along with its other housekeeping timers.
RUN systemctl mask apt-daily.timer apt-daily-upgrade.timer motd-news.timer dpkg-db-backup.timer

# journald never reads the kernel log. Under sysbox /dev/kmsg is not pollable and journald fails
# at boot, leaving no unit with logs; under privileged mode it is the host's kernel log.
COPY journald.conf /etc/systemd/journald.conf.d/10-container.conf

# The Docker engine runs as a service (its packages enable it already; this states it), and a timer
# removes unused images and build cache weekly. It never removes volumes or touches containers.
COPY docker-prune.service docker-prune.timer /etc/systemd/system/
RUN systemctl enable docker.service containerd.service docker-prune.timer

# dev's systemd user manager starts at boot, before any login: what `loginctl enable-linger dev` writes.
RUN install -d /var/lib/systemd/linger && touch /var/lib/systemd/linger/dev

ENTRYPOINT ["/sbin/init"]
