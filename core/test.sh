#!/bin/sh
# Usage: core/test.sh <image> [tools|docker]
# Runs every check against <image>, one ok/FAIL line each; exits non-zero if any failed.
set -eu

image=${1:?usage: test.sh <image> [tools|docker]}
group=${2:-all}
failed=0

pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; failed=1; }

# check_run <description> [docker run flags...] -- <command...>: run the command in a fresh container.
# On failure the captured output is shown, indented, under the FAIL line.
check_run() {
	desc=$1
	shift
	flags=
	while [ "$1" != -- ]; do
		flags="$flags $1"
		shift
	done
	shift
	# shellcheck disable=SC2086
	if out=$(docker run --rm $flags "$image" "$@" 2>&1); then
		pass "$desc"
	else
		fail "$desc"
		[ -z "$out" ] || printf '%s\n' "$out" | tail -n 20 | sed 's/^/     /'
	fi
}

# check <description> <command...>: check_run with no extra flags.
check() {
	desc=$1
	shift
	check_run "$desc" -- "$@"
}

group_tools() {
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
	if [ "$(docker inspect --format '{{json .Config.Entrypoint}}' "$image")" = null ]; then
		pass "no entrypoint"
	else
		fail "no entrypoint"
	fi
	check "fish login PATH" fish -l -c 'for t in git gh uv bun claude opencode docker; command -q $t; or exit 1; end'
}

group_docker() {
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
	tools) group_tools ;;
	docker) group_docker ;;
	all) group_tools; group_docker ;;
	*) echo "unknown group: $group" >&2; exit 2 ;;
esac

exit "$failed"
