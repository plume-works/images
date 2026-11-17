#!/bin/sh
# Usage: core/test.sh <image> [tools|docker]
set -eu

image=${1:?usage: test.sh <image> [tools|docker]}
group=${2:-all}
failed=0

check() {
	desc=$1
	shift
	if docker run --rm "$image" "$@" >/dev/null 2>&1; then
		echo "ok   $desc"
	else
		echo "FAIL $desc"
		failed=1
	fi
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

case $group in
all) tools ;;
tools) tools ;;
docker) ;;
*) echo "unknown group: $group" >&2; exit 2 ;;
esac

exit "$failed"
