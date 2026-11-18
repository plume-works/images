#!/usr/bin/env bash
# Smoke test for the core image. Usage: images/core/smoke.sh <image-ref>
#
# Runs the checks inside the image the way a CI job container would: as root,
# with no systemd. The Docker engine checks add what a job needing an engine adds:
# privileged mode and a volume at /var/lib/docker. Stops at the first failed check.
set -euo pipefail

image="${1:?usage: $0 <image-ref>}"

docker run --rm -i "$image" bash -s <<'CHECKS'
set -euo pipefail
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

# The default user is root, so the image works as a GitHub Actions job container.
[ "$(id -u)" = 0 ] || fail "default user is $(id -un), not root"
pass "default user is root"

# dev: UID 1000, bash login shell, passwordless sudo.
[ "$(id -u dev 2>/dev/null)" = 1000 ] || fail "no user dev at UID 1000"
[ "$(getent passwd dev | cut -d: -f7)" = /bin/bash ] || fail "dev's shell is not bash"
[ "$(su dev -c 'sudo -n id -u')" = 0 ] || fail "dev has no passwordless sudo"
pass "dev is UID 1000 with bash and passwordless sudo"

# Each tool answers, as root and as dev, from a system-wide location (not under a home).
for tool in git gh; do
  path=$(command -v "$tool") || fail "$tool is not on PATH"
  case "$(readlink -f "$path")" in
    /root/* | /home/*) fail "$tool resolves under a home directory: $path" ;;
  esac
  "$tool" --version | head -n1
  su dev -c "$tool --version" >/dev/null || fail "$tool does not run as dev"
done
pass "git and gh answer as root and as dev, from system-wide locations"
CHECKS

# Docker engine: started on demand by start-docker, the way a CI job container
# would run it (privileged, no systemd, a volume for the engine's storage).
docker run --rm -i --privileged --volume /var/lib/docker "$image" bash -s <<'CHECKS'
set -euo pipefail
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

docker --version
docker buildx version
docker compose version
id -nG dev | tr ' ' '\n' | grep -qx docker || fail "dev is not in the docker group"
pass "Docker CLI, Buildx and Compose answer; dev is in the docker group"

if docker info >/dev/null 2>&1; then fail "an engine is running before start-docker"; fi
start-docker || fail "start-docker did not bring the engine up"
docker info >/dev/null 2>&1 || fail "start-docker returned before the engine was ready"
pid=$(cat /run/docker.pid)
pass "start-docker starts the engine and returns once it is ready"

start-docker || fail "start-docker fails when an engine is already running"
su dev -c start-docker || fail "start-docker fails for dev when an engine is already running"
{ [ "$(cat /run/docker.pid)" = "$pid" ] && kill -0 "$pid"; } || fail "start-docker restarted a running engine"
pass "start-docker does nothing when an engine is already running"

docker pull -q hello-world >/dev/null
docker run --rm hello-world | grep -q 'Hello from Docker!' || fail "a container did not run as root"
su dev -c 'docker run --rm hello-world' | grep -q 'Hello from Docker!' || fail "a container did not run as dev"
docker run --rm --memory 64m hello-world >/dev/null || fail "a container with a memory limit did not run"
pass "the engine runs a container to completion, as root and as dev"
CHECKS

# Without a volume the engine's storage sits on the container's overlay filesystem,
# where containers cannot start: start-docker must fail and say how to fix it.
if out=$(docker run --rm --privileged "$image" start-docker 2>&1); then
  echo "FAIL: start-docker succeeded with /var/lib/docker on the container's overlay filesystem" >&2
  exit 1
fi
grep -q -- '--volume /var/lib/docker' <<<"$out" || {
  echo "FAIL: start-docker failed without naming the missing volume: $out" >&2
  exit 1
}
echo "ok: start-docker refuses to run without a volume for /var/lib/docker, and says so"

echo "core smoke test passed: $image"
