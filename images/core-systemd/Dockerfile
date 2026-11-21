# No USER line: systemd must run as root.
# CI (../docker-bake.hcl) always builds on this commit's core image; the default serves plain local builds.
ARG BASE_IMAGE=ghcr.io/plume-works/core:edge
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# dbus-user-session and libpam-systemd: what dev's per-user manager needs. From the core image's apt snapshot.
RUN apt-get update --error-on=any \
 && apt-get install -y --no-install-recommends systemd systemd-sysv dbus dbus-user-session libpam-systemd \
 && rm -rf /var/lib/apt/lists/*

COPY journald.conf /etc/systemd/journald.conf.d/10-container.conf

COPY docker-prune.service docker-prune.timer /etc/systemd/system/

# Units that cannot work in a container: kernel module loading, kernel debug and config mounts
# (they cannot mount under sysbox), binfmt, consoles (under privileged mode getty finds the host's
# ttys and restart-loops into a failed state), and filesystem maintenance of the host's disks.
RUN systemctl mask \
      systemd-modules-load.service \
      sys-kernel-debug.mount sys-kernel-tracing.mount sys-kernel-config.mount \
      sys-fs-fuse-connections.mount \
      proc-sys-fs-binfmt_misc.automount proc-sys-fs-binfmt_misc.mount systemd-binfmt.service \
      getty.target console-getty.service \
      e2scrub_all.timer fstrim.timer \
 # Nothing updates itself: the OS's periodic update timers are masked, not just disabled, so a
 # package upgrade cannot re-enable them; likewise its other housekeeping timers.
 && systemctl mask apt-daily.timer apt-daily-upgrade.timer motd-news.timer dpkg-db-backup.timer \
 && systemctl enable docker.service containerd.service docker-prune.timer \
 # dev's systemd user manager starts at boot, before any login: what `loginctl enable-linger dev` writes.
 && install -d /var/lib/systemd/linger && touch /var/lib/systemd/linger/dev

# docker stop sends systemd's shutdown signal, so the inner engine stops its containers cleanly.
# The image cannot set the stop timeout: give `docker stop` more than the default 10s (the inner
# engine itself waits 10s for a container that ignores SIGTERM).
STOPSIGNAL SIGRTMIN+3
ENTRYPOINT ["/sbin/init"]
