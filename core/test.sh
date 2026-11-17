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

case $group in
  tools) tools ;;
  all)   tools ;;
  *)     echo "unknown group: $group" >&2; exit 2 ;;
esac

exit "$failed"
