#!/usr/bin/env bash
# Smoke test for the core image. Usage: images/core/smoke.sh <image-ref>
#
# Runs the checks inside the image the way a CI job container would: as root,
# with no systemd and no extra options. Stops at the first failed check.
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

echo "core smoke test passed: $image"
