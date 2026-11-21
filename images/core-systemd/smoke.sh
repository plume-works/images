#!/usr/bin/env bash
# Smoke test for the core systemd image.
#
# Boots the image with its own entrypoint in privileged mode (hosted runners have no sysbox), with anonymous
# volumes for the inner engine's storage, and checks what booting adds to the core image.
# It does not repeat the core image's checks.
set -euo pipefail

image="${1:?usage: $0 <image-ref>}"
# shellcheck source=images/smoke-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../smoke-lib.sh"
smoke_init core-systemd

boot
pass "the system boots to a running state with no failed units"

[ "$(in_container ps -o comm= -p 1)" = systemd ] || fail "PID 1 is not systemd"
[ "$(in_container id -u)" = 0 ] || fail "the default user is not root"
pass "systemd is PID 1 from the image's own entrypoint; the default user is root"

[ -n "$(in_container journalctl -b --no-pager -n 5 -q)" ] || fail "the journal holds no entries"
in_container journalctl -b --no-pager -u docker.service -q | grep . >/dev/null || fail "the journal holds no entries for docker.service"
# In privileged mode /dev/kmsg is the host's kernel log (under sysbox it is not pollable at all):
# kernel messages in the journal mean journald reads it.
[ -z "$(in_container journalctl -b --no-pager -q _TRANSPORT=kernel)" ] || fail "journald reads the kernel log"
pass "journald holds entries, service logs included, and does not read the kernel log"

in_container systemctl is-active --quiet docker.service || fail "docker.service is not active after boot"
in_container docker pull -q hello-world >/dev/null
in_container docker run --rm hello-world | grep 'Hello from Docker!' >/dev/null || fail "a container did not run"
pass "the Docker service starts at boot and runs a container"

# Nobody has logged in: dev's user manager runs because of the image, not a session.
# (systemd gives the user manager its own session of class "manager"; that is not a login.)
logins=$(in_container loginctl list-sessions --no-legend | awk '$6 != "manager"')
[ -z "$logins" ] || fail "a login session exists, so the next check would prove nothing: $logins"
in_container systemctl is-active --quiet user@1000.service || fail "dev's user manager is not running"
state=$(docker exec -u dev -e XDG_RUNTIME_DIR=/run/user/1000 "$container" systemctl --user is-system-running) || true
[ "$state" = running ] || fail "dev's user manager is '$state', not running"
pass "dev's systemd user manager runs at boot without a login"

# Without --all, list-timers shows only the timers that are scheduled to fire.
timers=$(in_container systemctl list-timers --no-legend --no-pager)
for t in apt-daily.timer apt-daily-upgrade.timer motd-news.timer; do
  ! grep -qw "$t" <<<"$timers" || fail "the update timer $t is scheduled"
done
in_container systemctl is-active --quiet unattended-upgrades.service && fail "unattended-upgrades is running"
pass "the operating system's update timers are not scheduled"

grep -qw docker-prune.timer <<<"$timers" || fail "the Docker cleanup timer is not scheduled"
in_container systemctl is-active --quiet docker-prune.timer || fail "the Docker cleanup timer is not active"
pass "the Docker cleanup timer is scheduled"

# The cleanup the timer runs. hello-world is unused (its container was removed) but was pulled
# just now, so the cleanup as shipped keeps it.
in_container systemctl start docker-prune.service || fail "the Docker cleanup failed"
in_container docker image inspect hello-world >/dev/null 2>&1 || fail "the cleanup removed an image pulled just now"
pass "the cleanup runs and keeps an unused image pulled within the week"

# Shrink the week to a second, so everything here is "old", and check what the cleanup removes
# and what it must never touch. (Build cache that shares a layer with an image a container uses
# stays even under an unfiltered prune, so only unshared cache counts.)
private_cache() { in_container docker buildx du --format '{{if not .Shared}}{{.ID}}{{end}}' | grep -c . || true; }
in_container docker pull -q busybox >/dev/null
in_container docker run -d --name running busybox sleep infinity >/dev/null
in_container docker run --name stopped busybox true
in_container docker volume create unused-volume >/dev/null
docker exec -i "$container" docker build -q -t built - <<<$'FROM busybox\nRUN echo cache >/cache' >/dev/null
in_container docker image rm -f built >/dev/null
[ "$(private_cache)" -gt 0 ] || fail "the build left no build cache to clean"
in_container mkdir -p /run/systemd/system/docker-prune.service.d
docker exec -i "$container" tee /run/systemd/system/docker-prune.service.d/smoke.conf >/dev/null <<<$'[Service]\nEnvironment=UNUSED_FOR=1s'
in_container systemctl daemon-reload
sleep 2
in_container systemctl start docker-prune.service || fail "the Docker cleanup failed"
! in_container docker image inspect hello-world >/dev/null 2>&1 || fail "the cleanup kept an unused image"
[ "$(private_cache)" -eq 0 ] || fail "the cleanup kept unused build cache"
[ "$(in_container docker inspect -f '{{.State.Running}}' running)" = true ] || fail "the cleanup touched a running container"
in_container docker inspect stopped >/dev/null 2>&1 || fail "the cleanup removed a stopped container"
in_container docker image inspect busybox >/dev/null 2>&1 || fail "the cleanup removed an image a container uses"
in_container docker volume inspect unused-volume >/dev/null 2>&1 || fail "the cleanup removed a volume"
pass "the cleanup removes unused images and build cache, never containers, their images or volumes"

# Stop: docker stop must shut systemd down, and with it the inner engine and its containers.
# `running` (sleep as PID 1) ignores SIGTERM, so the inner engine waits its own 10s before killing
# it; the generous timeout leaves room for that. Exit code 137 would mean the stop timed out and
# the container was killed instead.
docker stop -t 60 "$container" >/dev/null
code=$(docker inspect -f '{{.State.ExitCode}}' "$container")
[ "$code" != 137 ] || fail "docker stop killed the container instead of shutting systemd down"
[ "$code" = 130 ] || fail "the container exited with $code, not 130 (systemd's halt in a container)"
pass "docker stop shuts systemd down cleanly"

boot again
in_container docker info >/dev/null 2>&1 || fail "the inner engine did not come back on the same storage"
[ "$(in_container docker inspect -f '{{.State.ExitCode}}' running)" = 137 ] || fail "the inner engine did not stop its containers"
in_container docker start running >/dev/null || fail "a container stopped by the shutdown does not start again"
pass "the inner engine stopped its containers on shutdown and starts again on the same volumes"

echo "core-systemd smoke test passed: $image"
