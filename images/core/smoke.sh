#!/usr/bin/env bash
# Smoke test for the core image.
#
# Runs the checks inside the image the way a CI job container would: as root,
# with no systemd. The Docker engine checks add only what a job needing an engine adds:
# privileged mode and an anonymous volume at /var/lib/docker (hosted runners have no sysbox).
set -euo pipefail

image="${1:?usage: $0 <image-ref>}"

docker run --rm -i "$image" bash -s <<'CHECKS'
set -euo pipefail
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

# The default user is root, so the image works as a GitHub Actions job container.
[ "$(id -u)" = 0 ] || fail "default user is $(id -un), not root"
pass "default user is root"

# Nothing is installed under a home directory: before anything has run, the homes hold only shell
# start-up files. That includes agent settings, plugins, skills, MCP servers and credentials.
for home in /root /home/dev; do
  extra=$(find "$home" -mindepth 1 -maxdepth 1 ! -name .bashrc ! -name .profile ! -name .bash_logout)
  [ -z "$extra" ] || fail "$home ships more than shell start-up files: $extra"
done
pass "the homes of root and dev hold only shell start-up files"

# dev: UID 1000, bash login shell, passwordless sudo.
[ "$(id -u dev 2>/dev/null)" = 1000 ] || fail "no user dev at UID 1000"
[ "$(getent passwd dev | cut -d: -f7)" = /bin/bash ] || fail "dev's shell is not bash"
[ "$(su dev -c 'sudo -n id -u')" = 0 ] || fail "dev has no passwordless sudo"
pass "dev is UID 1000 with bash and passwordless sudo"

# Each tool answers, as root and as dev, from a system-wide location (not under a home).
as() { if [ "$1" = root ]; then bash -c "$2"; else su "$1" -c "$2"; fi; }
for tool in git gh git-lfs uv uvx python python3 bun bunx cmake ninja fish jq tmux btop claude opencode; do
  for user in root dev; do
    path=$(as "$user" "command -v $tool") || fail "$tool is not on $user's PATH"
    case "$(readlink -f "$path")" in
      /root/* | /home/*) fail "$tool resolves under a home directory for $user: $path" ;;
    esac
    # Capture, then keep the first line: piping into head under pipefail can kill a multi-line writer.
    flag=--version; [ "$tool" = tmux ] && flag=-V
    version=$(as "$user" "$tool $flag" 2>&1) || fail "$tool does not run as $user"
    version=${version%%$'\n'*}
    [ -n "$version" ] || fail "$tool reports no version as $user"
  done
  echo "$tool: $version"
done
pass "every tool answers as root and as dev, from system-wide locations"

# OpenCode is version 2, the line whose `opencode serve` runs the web UI a workspace app proxies to.
case "$(opencode --version)" in
  "opencode v2."*) pass "opencode is version 2 ($(opencode --version))" ;;
  *) fail "opencode is $(opencode --version), not version 2" ;;
esac

# The Python is Ubuntu's, and a virtual environment dev makes with uv gets it too, not a per-user download.
for py in python python3; do
  case "$(readlink -f "$(command -v $py)")" in
    /usr/bin/python3*) ;;
    *) fail "$py is $(readlink -f "$(command -v $py)"), not Ubuntu's Python" ;;
  esac
done
pass "python and python3 are Ubuntu's ($(python3 --version))"
venv_python=$(su dev -c 'cd "$(mktemp -d)" && uv venv -q v && readlink -f v/bin/python') \
  || fail "uv venv fails as dev"
case "$venv_python" in
  /usr/bin/python3*) ;;
  *) fail "uv venv as dev uses $venv_python, not Ubuntu's Python" ;;
esac
pass "uv venv as dev uses Ubuntu's Python ($venv_python)"

# No Node.js: Bun covers that need.
for tool in node nodejs npm npx; do
  if command -v "$tool" >/dev/null; then fail "$tool is installed"; fi
done
pass "Node.js is not installed"

# says PATTERN COMMAND...: the command's output, stdout and stderr whatever its exit status, matches PATTERN.
# (Capturing first, rather than piping into grep -q, keeps pipefail from tripping on a closed pipe.)
says() { local pattern=$1 out; shift; out=$("$@" 2>&1) || :; grep -qE -- "$pattern" <<<"$out"; }

# git gets a GitHub credential from the token in the environment, through the GitHub CLI, as root and as dev.
# No network is needed: gh hands back the token it finds. Without a token git must fail, not hang on a prompt.
fill='printf "protocol=https\nhost=github.com\n\n" | GIT_TERMINAL_PROMPT=0 timeout 20 git credential fill'
for user in root dev; do
  for var in GH_TOKEN GITHUB_TOKEN; do
    says "^password=smoke-token-$var\$" as "$user" "export $var=smoke-token-$var; $fill" \
      || fail "git obtains no credential from $var as $user"
  done
  if as "$user" "unset GH_TOKEN GITHUB_TOKEN; $fill" >/dev/null 2>&1; then
    fail "git obtained a credential with no token as $user"
  fi
done
pass "git obtains a credential from GH_TOKEN or GITHUB_TOKEN through gh, as root and as dev"

# The agents are bare: no MCP servers, plugins or credentials, as root and as dev.
# OpenCode 2's commands talk to a server: --standalone runs a private one for the command, rather than leaving a
# per-user background service behind (whose fixed port root's and dev's would contend for).
for user in root dev; do
  says '^No MCP servers configured' as "$user" 'claude mcp list' || fail "claude has MCP servers as $user"
  says '^No plugins installed' as "$user" 'claude plugin list' || fail "claude has plugins as $user"
  says '"loggedIn": false' as "$user" 'claude auth status' || fail "claude is signed in as $user"
  for args in 'mcp list:^No MCP servers configured' 'plugin list:^No plugins found' 'auth list:^No authenticated integrations'; do
    says "${args#*:}" as "$user" "timeout 60 opencode --standalone ${args%%:*}" || fail "opencode ${args%%:*} is not empty as $user"
  done
done
pass "claude and opencode are bare: no MCP servers, plugins or credentials"

# Self-updating is off system-wide for both agents, however a shell is entered: as the image runs (a CI job),
# as dev through su, and in a fresh login of dev, which drops the image's environment. Claude Code also
# refuses with no environment at all. OpenCode checks for updates when its terminal UI starts, so the UI is run
# for a few seconds in a pseudo-terminal, with its log on stderr, to see it skip the check. Its input is /dev/null:
# script would otherwise read the rest of these checks from this shell's standard input.
opencode_ui='cd /tmp && timeout 8 script -qec "opencode --standalone --print-logs 2>&1" /dev/null'
for how in "as root" "as dev" "su -l dev -c"; do
  # $how is a command and its leading arguments, so it is left unquoted to split.
  says 'Updates are disabled' $how 'timeout 60 claude update' || fail "claude update is not refused ($how)"
  says 'message="update check skipped" reason=disabled' $how "$opencode_ui" </dev/null \
    || fail "OpenCode's update check is on ($how)"
done
says 'Updates are disabled' env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=/root claude update \
  || fail "claude update is not refused with an empty environment"
pass "self-updating is off for claude and opencode, as root, as dev and in a fresh login"
CHECKS

# Docker engine: started on demand by start-docker, the way a CI job container
# would run it: privileged, no systemd, and a volume at /var/lib/docker.
docker run --rm -i --privileged -v /var/lib/docker "$image" bash -s <<'CHECKS'
set -euo pipefail
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

docker --version
docker buildx version
docker compose version
id -nG dev | tr ' ' '\n' | grep -x docker >/dev/null || fail "dev is not in the docker group"
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
docker run --rm hello-world | grep 'Hello from Docker!' >/dev/null || fail "a container did not run as root"
su dev -c 'docker run --rm hello-world' | grep 'Hello from Docker!' >/dev/null || fail "a container did not run as dev"
docker run --rm --memory 64m hello-world >/dev/null || fail "a container with a memory limit did not run"
pass "the engine runs a container to completion, as root and as dev"
CHECKS

# refuses WHY PATTERN DOCKER-RUN-ARGS...: start-docker, run in a container made from these arguments, fails,
# and its output matches PATTERN. WHY describes the setup, for the failure message.
refuses() {
  local why=$1 pattern=$2 out
  shift 2
  if out=$(docker run --rm "$@" 2>&1); then
    echo "FAIL: start-docker succeeded $why" >&2
    exit 1
  fi
  grep -E -- "$pattern" <<<"$out" >/dev/null || {
    echo "FAIL: start-docker failed $why, but did not say why: $out" >&2
    exit 1
  }
}

# Privileged with no volume at /var/lib/docker leaves the engine's storage on the container's overlay filesystem,
# where containers cannot start: start-docker must fail and say how to fix it.
refuses "with /var/lib/docker on the container's overlay filesystem" 'mount a volume at /var/lib/docker' \
  --privileged "$image" start-docker
echo "ok: start-docker refuses to run with its storage on the overlay filesystem, and says so"

# Without --privileged (or sysbox) the engine cannot run: start-docker must say so, not wait out its timeout.
refuses "in a container that is not privileged" 'run it with --privileged' -v /var/lib/docker "$image" start-docker
echo "ok: start-docker refuses to run in a container that is not privileged, and says so"

# A dockerd that exits at once (here: a broken daemon.json) fails start-docker at once, and it says so.
# The outer timeout is well under START_DOCKER_TIMEOUT's 60 s, so waiting it out fails with no message.
refuses "with a dockerd that exits at once" 'dockerd exited before the engine was ready' \
  --privileged -v /var/lib/docker "$image" sh -c 'mkdir -p /etc/docker && echo "{" >/etc/docker/daemon.json && exec timeout 20 start-docker'
echo "ok: start-docker fails at once when dockerd exits, and says so"

echo "core smoke test passed: $image"
