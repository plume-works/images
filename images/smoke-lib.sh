# shellcheck shell=bash
# Shared helpers for the smoke tests of the images that boot systemd.
#
# Under `set -o pipefail`, never pipe into `grep -q`: it exits at the first match, the writer can die of SIGPIPE,
# and the pipeline then fails although the line was there. Use `grep … >/dev/null`, which reads all its input.
#
# In privileged mode the inner engine's storage needs volumes: the container gets anonymous ones, which a stopped
# container keeps when it starts again. (Under sysbox it would need none.)

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
  trap smoke_cleanup EXIT
}

smoke_cleanup() {
  docker rm -f --volumes "$container" >/dev/null 2>&1 || true
  if declare -F cleanup_extra >/dev/null; then cleanup_extra; fi
}

# boot: run a new container from $image. boot again: start the stopped one.
boot() {
  if [ "${1:-}" = again ]; then
    docker start "$container" >/dev/null
  else
    docker run -d --name "$container" --privileged -v /var/lib/docker -v /var/lib/containerd "${image:?set by the caller}" >/dev/null
  fi
  local state
  state=$(wait_system_running in_container)
  [ "$state" = running ] || fail "system state after boot is '$state', not running"
  [ -z "$(in_container systemctl --failed --no-legend)" ] || fail "units failed at boot"
}
