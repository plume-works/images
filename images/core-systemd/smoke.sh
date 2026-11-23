#!/usr/bin/env bash
# Privileged mode: hosted runners have no sysbox. It does not repeat the core image's checks.
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
in_container systemctl show docker-prune.timer -p TimersCalendar --value | grep 'OnCalendar=\*-\*-\* 00:00:00' >/dev/null \
  || fail "the Docker cleanup timer is not daily"
pass "the Docker cleanup timer is scheduled daily"

# What the cleanup can remove: a stopped container with an anonymous volume, a named volume no container uses,
# an unused image (hello-world, whose container was removed) and build cache. What it must never touch: a running
# container and the image it uses. (Build cache that shares a layer with an image a container uses stays even
# under an unfiltered prune, so only unshared cache counts.)
private_cache() { in_container docker buildx du --format '{{if not .Shared}}{{.ID}}{{end}}' | grep -c . || true; }
in_container docker pull -q busybox >/dev/null
in_container docker run -d --name running busybox sleep infinity >/dev/null
in_container docker run --name stopped -v /data busybox true
anonymous=$(in_container docker inspect -f '{{range .Mounts}}{{.Name}}{{end}}' stopped)
in_container docker volume create named-volume >/dev/null
docker exec -i "$container" docker build -q -t built - <<<$'FROM busybox\nRUN echo cache >/cache' >/dev/null
in_container docker image rm -f built >/dev/null
[ "$(private_cache)" -gt 0 ] || fail "the build left no build cache to clean"

kept_all() {
  in_container docker inspect stopped >/dev/null 2>&1 || fail "the cleanup $1 removed a stopped container"
  in_container docker volume inspect "$anonymous" >/dev/null 2>&1 || fail "the cleanup $1 removed an anonymous volume"
  in_container docker volume inspect named-volume >/dev/null 2>&1 || fail "the cleanup $1 removed a named volume"
  in_container docker image inspect hello-world >/dev/null 2>&1 || fail "the cleanup $1 removed an unused image"
  [ "$(private_cache)" -gt 0 ] || fail "the cleanup $1 removed build cache"
}
settings() {
  in_container mkdir -p /run/systemd/system/docker-prune.service.d
  docker exec -i "$container" tee /run/systemd/system/docker-prune.service.d/smoke.conf >/dev/null <<<"[Service]
$(for kind in STOPPED_CONTAINERS ANONYMOUS_VOLUMES NAMED_VOLUMES IMAGES BUILD_CACHE; do echo "Environment=PRUNE_$kind=$1"; done)"
  in_container systemctl daemon-reload
}

in_container systemctl start docker-prune.service || fail "the Docker cleanup failed"
kept_all "as shipped"
pass "the cleanup as shipped keeps everything made within the week"

settings off
sleep 2
in_container systemctl start docker-prune.service || fail "the Docker cleanup failed"
kept_all "with every kind off"
pass "the cleanup with every kind off removes nothing"

# Shrink every age, named volumes' included, to a second, so everything here is "old".
settings 1s
# systemd's PATH puts /usr/local/bin before /usr/bin, so this docker shadows the real one in the cleanup.
docker exec -i "$container" sh -c 'cat >/usr/local/bin/docker && chmod +x /usr/local/bin/docker' <<'WRAPPER'
#!/bin/sh
[ "$1" = rm ] && exit 1
exec /usr/bin/docker "$@"
WRAPPER
! in_container systemctl start docker-prune.service 2>/dev/null || fail "the cleanup succeeded although a container removal failed"
in_container docker inspect stopped >/dev/null 2>&1 || fail "the cleanup removed a stopped container although docker rm failed"
! in_container docker volume inspect named-volume >/dev/null 2>&1 || fail "a failed container removal kept an unused named volume"
! in_container docker image inspect hello-world >/dev/null 2>&1 || fail "a failed container removal kept an unused image"
[ "$(private_cache)" -eq 0 ] || fail "a failed container removal kept unused build cache"
pass "a kind that fails fails the cleanup, and the kinds after it still run"
in_container rm /usr/local/bin/docker
in_container systemctl reset-failed docker-prune.service

in_container systemctl start docker-prune.service || fail "the Docker cleanup failed"
! in_container docker inspect stopped >/dev/null 2>&1 || fail "the cleanup kept a stopped container"
! in_container docker volume inspect "$anonymous" >/dev/null 2>&1 || fail "the cleanup kept an unused anonymous volume"
! in_container docker volume inspect named-volume >/dev/null 2>&1 || fail "the cleanup kept an unused named volume"
! in_container docker image inspect hello-world >/dev/null 2>&1 || fail "the cleanup kept an unused image"
[ "$(private_cache)" -eq 0 ] || fail "the cleanup kept unused build cache"
[ "$(in_container docker inspect -f '{{.State.Running}}' running)" = true ] || fail "the cleanup touched a running container"
in_container docker image inspect busybox >/dev/null 2>&1 || fail "the cleanup removed an image a container uses"
pass "the cleanup removes each kind once older than its age, never a running container or its image"

settings 7d
! in_container systemctl start docker-prune.service 2>/dev/null || fail "the cleanup accepted an age without a Go duration unit"
pass "the cleanup refuses an age Docker's filters do not take"
in_container systemctl reset-failed docker-prune.service
in_container rm /run/systemd/system/docker-prune.service.d/smoke.conf
in_container systemctl daemon-reload

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
