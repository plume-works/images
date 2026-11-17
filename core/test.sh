#!/bin/sh
# Usage: core/test.sh <image> [tools|docker]
set -eu

image=${1:?usage: test.sh <image> [tools|docker]}
group=${2:-all}
failed=0

# Usage: check_run <desc> [docker run flags...] -- <command...>
check_run() {
	desc=$1
	shift
	flags=
	while [ "$1" != -- ]; do
		flags="$flags $1"
		shift
	done
	shift
	out=$(mktemp)
	# shellcheck disable=SC2086
	if docker run --rm $flags "$image" "$@" >"$out" 2>&1; then
		echo "ok   $desc"
	else
		echo "FAIL $desc"
		sed 's/^/     /' "$out"
		failed=1
	fi
	rm -f "$out"
}

check() {
	desc=$1
	shift
	check_run "$desc" -- "$@"
}

tools() {
	check "git"            git --version
	check "git-lfs"        git lfs version
	check "gh"             gh --version
	check "uv"             uv --version
	check "uvx"            uvx --version
	check "node 24"        sh -c 'node --version | grep -q "^v24\."'
	check "npm"            npm --version
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
	check "fish login PATH" fish -l -c 'for t in git gh uv node bun claude opencode docker; command -q $t; or exit 1; end'
	if [ "$(docker inspect --format '{{json .Config.Entrypoint}}' "$image")" = null ]; then
		echo "ok   no entrypoint"
	else
		echo "FAIL no entrypoint"
		failed=1
	fi
}

docker_tests() {
	# privileged: daemon comes up, dev can use it, second call is a no-op
	check_run "dockerd starts"      --privileged -- sh -c 'start-dockerd && docker run --rm hello-world'
	check_run "dev without sudo"    --privileged -- sh -c 'start-dockerd && docker info >/dev/null'
	check_run "idempotent"          --privileged -- sh -c 'start-dockerd && start-dockerd && [ "$(pgrep -xc dockerd)" = 1 ]'
	# unprivileged: fails fast with the log, does not hang
	check_run "fails unprivileged"  -e START_DOCKERD_TIMEOUT=5 -- sh -c '! timeout 20 start-dockerd 2>/tmp/err && [ -s /tmp/err ]'
	# not started by default
	check_run "inert by default"    -- sh -c '! pgrep -x dockerd'
}

case $group in
all) tools; docker_tests ;;
tools) tools ;;
docker) docker_tests ;;
*) echo "unknown group: $group" >&2; exit 2 ;;
esac

exit "$failed"
