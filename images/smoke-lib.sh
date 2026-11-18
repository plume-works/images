# shellcheck shell=bash
# Shared helpers for the smoke tests of the images that boot systemd. Sourced, not run:
#   source "$(dirname "${BASH_SOURCE[0]}")/../smoke-lib.sh"
#
# $container is the container under test (a name or an ID), or empty while there is none. fail dumps its failed
# units and the end of its journal, plus whatever an optional `dump_extra` function in the caller prints.
#
# A script that starts the container itself (docker run, privileged: hosted runners have no sysbox) calls
#   smoke_init <prefix>   to name the container and its volumes, and remove both on exit
#   boot [again]          to start it (again: the stopped one) and wait for a running system with no failed units
# and runs commands in it with in_container. The cleanup on exit runs an optional `cleanup_extra` function too.

container=""

pass() { echo "ok: $*"; }

fail() {
  echo "FAIL: $*" >&2
  if [ -n "$container" ] && [ "$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null)" = true ]; then
    docker exec "$container" systemctl --failed --no-pager >&2 || true
    if declare -F dump_extra >/dev/null; then dump_extra >&2 || true; fi
    docker exec "$container" journalctl -b --no-pager 2>/dev/null | tail -n 50 >&2 || true
  fi
  exit 1
}

in_container() { docker exec "$container" "$@"; }

# wait_system_running EXEC...: the system's state once systemd has settled, read through EXEC (a command prefix
# that runs a command in the container). PID 1 answers on the bus only after a moment; until then
# is-system-running prints nothing. The timeout runs inside the container: one around the exec would not stop a
# hung exec.
wait_system_running() {
  local state=""
  for _ in $(seq 30); do
    state=$("$@" timeout 120 systemctl is-system-running --wait 2>/dev/null) || true
    [ -n "$state" ] && break
    sleep 1
  done
  echo "$state"
}

smoke_init() {
  container="$1-smoke-$$"
  # Storage for the inner engine. Named so a second boot reuses them; never shared with another running container.
  volumes=("$container-docker:/var/lib/docker" "$container-containerd:/var/lib/containerd")
  trap smoke_cleanup EXIT
}

smoke_cleanup() {
  docker rm -f "$container" >/dev/null 2>&1 || true
  for v in "${volumes[@]}"; do docker volume rm "${v%%:*}" >/dev/null 2>&1 || true; done
  if declare -F cleanup_extra >/dev/null; then cleanup_extra; fi
}

# boot: run a new container from $image. boot again: start the stopped one.
boot() {
  if [ "${1:-}" = again ]; then
    docker start "$container" >/dev/null
  else
    docker run -d --name "$container" --privileged \
      --volume "${volumes[0]}" --volume "${volumes[1]}" "${image:?set by the caller}" >/dev/null
  fi
  local state
  state=$(wait_system_running in_container)
  [ "$state" = running ] || fail "system state after boot is '$state', not running"
  [ -z "$(in_container systemctl --failed --no-legend)" ] || fail "units failed at boot"
}
