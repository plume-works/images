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
for tool in git gh git-lfs uv uvx python python3 bun bunx cmake ninja fish claude opencode; do
  for user in root dev; do
    path=$(as "$user" "command -v $tool") || fail "$tool is not on $user's PATH"
    case "$(readlink -f "$path")" in
      /root/* | /home/*) fail "$tool resolves under a home directory for $user: $path" ;;
    esac
    version=$(as "$user" "$tool --version" 2>&1 | head -n1) || fail "$tool does not run as $user"
    [ -n "$version" ] || fail "$tool reports no version as $user"
  done
  echo "$tool: $version"
done
pass "every tool answers as root and as dev, from system-wide locations"

# A virtual environment dev makes gets the Python uv manages system-wide, not a per-user download
# and not the distribution's.
venv_python=$(su dev -c 'cd "$(mktemp -d)" && uv venv -q v && readlink -f v/bin/python') \
  || fail "uv venv fails as dev"
case "$venv_python" in
  /root/* | /home/* | /usr/bin/*) fail "uv venv as dev uses $venv_python, not uv's system-wide Python" ;;
esac
pass "uv venv as dev uses the system-wide Python ($venv_python)"

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
for user in root dev; do
  says '^No MCP servers configured' as "$user" 'claude mcp list' || fail "claude has MCP servers as $user"
  says '^No plugins installed' as "$user" 'claude plugin list' || fail "claude has plugins as $user"
  says '"loggedIn": false' as "$user" 'claude auth status' || fail "claude is signed in as $user"
  says 'No MCP servers configured' as "$user" 'timeout 60 opencode mcp list' || fail "opencode has MCP servers as $user"
  says ' 0 credentials' as "$user" 'timeout 60 opencode auth list' || fail "opencode has credentials as $user"
done
pass "claude and opencode are bare: no MCP servers, plugins or credentials"

# Self-updating is off system-wide for both agents, however a shell is entered: as the image runs (a CI job),
# as dev through su, and in a fresh login of dev, which drops the image's environment. Claude Code also
# refuses with no environment at all.
for how in "as root" "as dev" "su -l dev -c"; do
  # shellcheck disable=SC2086 # $how is a command and its leading arguments
  says 'Updates are disabled' $how 'timeout 60 claude update' || fail "claude update is not refused ($how)"
  # shellcheck disable=SC2086
  [ "$($how 'printenv OPENCODE_DISABLE_AUTOUPDATE')" = 1 ] || fail "OpenCode's update check is on ($how)"
done
says 'Updates are disabled' env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=/root claude update \
  || fail "claude update is not refused with an empty environment"
pass "self-updating is off for claude and opencode, as root, as dev and in a fresh login"
CHECKS

echo "core smoke test passed: $image"
