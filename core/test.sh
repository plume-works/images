#!/bin/sh
# Acceptance test for the core image.
# Usage: core/test.sh <image> [tools|docker]
set -eu

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "usage: $0 <image> [tools|docker]" >&2
  exit 2
fi
image=$1
group=${2:-all}
failed=0

pass() { echo "ok $1"; }
fail() { echo "FAIL $1"; failed=1; }

# check <description> <command...>: run <command> in a fresh container.
check() {
  desc=$1
  shift
  if docker run --rm "$image" "$@" >/dev/null 2>&1; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

# check_run <description> <docker run flags...> -- <command...>
# Like check, with extra `docker run` flags before the image.
check_run() {
  desc=$1
  shift
  nflags=0
  for arg; do
    [ "$arg" = -- ] && break
    nflags=$((nflags + 1))
  done
  ncmd=$(($# - nflags - 1))
  # Reorder "flags -- command" into "flags image command" without eval.
  i=0; while [ "$i" -lt "$nflags" ]; do set -- "$@" "$1"; shift; i=$((i + 1)); done
  shift
  set -- "$@" "$image"
  i=0; while [ "$i" -lt "$ncmd" ]; do set -- "$@" "$1"; shift; i=$((i + 1)); done
  if docker run --rm "$@" >/dev/null 2>&1; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

tools() {
  check "git"            git --version
  check "git-lfs"        git lfs version
  check "gh"             gh --version
  check "uv"             uv --version
  check "uvx"            uvx --version
  check "bun"            bun --version
  check "claude"         claude --version
  check "opencode"       opencode --version
  check "gcc"            gcc --version
  check "make"           make --version
  check "curl"           curl --version
  check "jq"             jq --version
  check "rg"             rg --version
  check "less"           less --version
  check "docker cli"     docker --version
  check "buildx"         docker buildx version
  check "compose"        docker compose version
  check "user is dev"    sh -c '[ "$(id -un)" = dev ] && [ "$(id -u)" = 1000 ] && [ "$(id -g)" = 1000 ]'
  check "sudo"           sudo -n true
  check "login shell"    sh -c '[ "$(getent passwd dev | cut -d: -f7)" = /usr/bin/fish ]'
  check "home owned"     sh -c '[ -z "$(find /home/dev ! -user dev -o ! -group dev)" ]'
  # Host-side: the image must not set an entrypoint.
  if [ "$(docker inspect --format '{{json .Config.Entrypoint}}' "$image" 2>/dev/null)" = null ]; then
    pass "no entrypoint"
  else
    fail "no entrypoint"
  fi
  check "fish login PATH" fish -l -c 'for t in git gh uv bun claude opencode docker; command -q $t; or exit 1; end'
}

docker_group() {
  # privileged: daemon comes up, dev can use it, second call is a no-op.
  # No -v here: the image's own VOLUME must be what keeps /var/lib/docker off the overlay root.
  check_run "dockerd starts"      --privileged -- sh -c 'start-dockerd && docker run --rm hello-world'
  check_run "dev without sudo"    --privileged -- sh -c 'start-dockerd && docker info >/dev/null'
  check_run "idempotent"          --privileged -- sh -c 'start-dockerd && start-dockerd && [ "$(pgrep -xc dockerd)" = 1 ]'
  check_run "data on a volume"    -- sh -c 'grep -q " /var/lib/docker " /proc/mounts'
  # unprivileged: the script's own timeout fires (exit 1, log tail on stderr); it does not hang.
  # Exit 1 exactly: 127 would mean the script is missing, 124 that the outer timeout fired.
  check_run "fails unprivileged"  -e START_DOCKERD_TIMEOUT=5 -- sh -c 'timeout 20 start-dockerd 2>/tmp/err; [ $? = 1 ] && [ -s /tmp/err ]'
  # not started by default
  check_run "inert by default"    -- sh -c '! pgrep -x dockerd'
}

case $group in
  tools)  tools ;;
  docker) docker_group ;;
  all)    tools; docker_group ;;
  *)     echo "unknown group: $group" >&2; exit 2 ;;
esac

exit "$failed"
