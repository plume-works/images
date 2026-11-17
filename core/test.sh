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

# fail <description> [detail]: report a failure, with its cause indented below.
fail() {
  echo "FAIL $1"
  [ -z "${2-}" ] || printf '%s\n' "$2" | tail -n 20 | sed 's/^/    /'
  failed=1
}

# run_check <description> <docker run args...>: run, report, show output on failure.
run_check() {
  desc=$1
  shift
  if out=$(docker run --rm "$@" 2>&1); then
    pass "$desc"
  else
    status=$?
    fail "$desc" "${out:+$out
}(exit $status)"
  fi
}

# check <description> <command...>: run <command> in a fresh container.
check() {
  desc=$1
  shift
  run_check "$desc" "$image" "$@"
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
  run_check "$desc" "$@"
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
  check "user is dev"    sh -c 'id; [ "$(id -un)" = dev ] && [ "$(id -u)" = 1000 ] && [ "$(id -g)" = 1000 ]'
  check "sudo"           sudo -n true
  check "login shell"    sh -c 's=$(getent passwd dev | cut -d: -f7); echo "login shell: $s"; [ "$s" = /usr/bin/fish ]'
  check "home owned"     sh -c '[ -d /home/dev ] || { echo "no /home/dev"; exit 1; }; f=$(find /home/dev ! -user dev -o ! -group dev); [ -z "$f" ] || { echo "not dev:dev:"; echo "$f"; exit 1; }'
  # Host-side: the image must not set an entrypoint.
  entrypoint=$(docker inspect --format '{{json .Config.Entrypoint}}' "$image" 2>&1) || true
  if [ "$entrypoint" = null ]; then
    pass "no entrypoint"
  else
    fail "no entrypoint" "entrypoint: $entrypoint"
  fi
  check "fish login PATH" fish -l -c 'for t in git gh uv bun claude opencode docker; command -q $t; or begin; echo "not on PATH: $t"; exit 1; end; end'
  # Where `uv tool install` and `bun add -g` put a user's own tools.
  check "user bins on PATH" sh -c 'mkdir -p ~/.local/bin ~/.bun/bin &&
    printf "#!/bin/sh\n" > ~/.local/bin/uvtool && printf "#!/bin/sh\n" > ~/.bun/bin/buntool &&
    chmod +x ~/.local/bin/uvtool ~/.bun/bin/buntool &&
    uvtool && buntool && fish -l -c "uvtool; and buntool"'
}

docker_group() {
  # privileged: daemon comes up, dev can use it, second call is a no-op.
  # No -v here: the image's own VOLUME must be what keeps /var/lib/docker off the overlay root.
  check_run "dockerd starts"      --privileged -- sh -c 'start-dockerd && docker run --rm hello-world'
  check_run "dev without sudo"    --privileged -- sh -c 'start-dockerd && docker info >/dev/null'
  check_run "idempotent"          --privileged -- sh -c 'start-dockerd && start-dockerd && n=$(pgrep -xc dockerd); echo "dockerd processes: $n"; [ "$n" = 1 ]'
  check_run "data on a volume"    -- sh -c 'grep -q " /var/lib/docker " /proc/mounts || { echo "/var/lib/docker is not a mount"; exit 1; }'
  # unprivileged: the script's own timeout fires (exit 1, log tail on stderr); it does not hang.
  # Exit 1 exactly: 127 would mean the script is missing, 124 that the outer timeout fired.
  check_run "fails unprivileged"  -e START_DOCKERD_TIMEOUT=5 -- sh -c 'timeout 20 start-dockerd 2>/tmp/err; s=$?; [ $s = 1 ] && [ -s /tmp/err ] && exit 0; echo "start-dockerd exit $s (want 1, with the log tail on stderr); its stderr:"; cat /tmp/err; exit 1'
  # not started by default
  check_run "inert by default"    -- sh -c '! pgrep -ax dockerd'
}

case $group in
  tools)  tools ;;
  docker) docker_group ;;
  all)    tools; docker_group ;;
  *)     echo "unknown group: $group" >&2; exit 2 ;;
esac

exit "$failed"
