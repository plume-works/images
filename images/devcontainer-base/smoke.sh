#!/usr/bin/env bash
# Smoke test for the devcontainer base image. Usage: images/devcontainer-base/smoke.sh <image-ref>
#
# Brings the image up the way a consumer does: with the devcontainer CLI, from a devcontainer.json
# holding the image and the README's privileged-mode snippet (hosted runners have no sysbox).
# The image's metadata label is its interface, and a plain `docker run` would not read it.
# It does not repeat the core systemd image's checks. Stops at the first failed check.
#
# Needs Node (npx) or Bun (bunx) to run the devcontainer CLI, and a Docker daemon that sees this
# machine's /tmp (true on a GitHub runner and wherever the daemon is local).
set -euo pipefail

image="${1:?usage: $0 <image-ref>}"
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readme="$here/../../README.md"

# renovate: datasource=npm depName=@devcontainers/cli
DEVCONTAINER_CLI_VERSION=0.90.0

devcontainer() {
  # The CLI builds derived images (dev's UID, Features) on the image under test, which exists only
  # in the local image store. A docker-container builder (CI's setup-buildx-action) cannot see it.
  if command -v npx >/dev/null; then
    BUILDX_BUILDER=default npx --yes "@devcontainers/cli@$DEVCONTAINER_CLI_VERSION" "$@"
  else
    BUILDX_BUILDER=default bunx "@devcontainers/cli@$DEVCONTAINER_CLI_VERSION" "$@"
  fi
}

ws=$(mktemp -d "${TMPDIR:-/tmp}/devcontainer-base-smoke.XXXXXX")
mkdir "$ws/.devcontainer"
config="$ws/.devcontainer/devcontainer.json"

devcontainer_ids() { docker ps -aq --filter "label=devcontainer.local_folder=$ws"; }
# The snippet's named volumes, recorded while a container uses them: a failed rebuild removes the
# container but leaves its volumes.
snippet_volumes=""
record_volumes() {
  local ids
  ids=$(devcontainer_ids)
  # shellcheck disable=SC2086 # one ID per word
  [ -z "$ids" ] || snippet_volumes+=" $(docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}} {{end}}{{end}}' $ids)"
}
cleanup() {
  local ids
  record_volumes
  ids=$(devcontainer_ids)
  # shellcheck disable=SC2086
  [ -z "$ids" ] || docker rm -f $ids >/dev/null 2>&1 || true
  tr ' ' '\n' <<<"$snippet_volumes" | grep . | sort -u | xargs -r docker volume rm >/dev/null 2>&1 || true
  # The CLI's derived images are named after the workspace folder.
  docker images -q --filter "reference=vsc-$(basename "$ws" | tr '[:upper:]' '[:lower:]')-*" |
    xargs -r docker rmi -f >/dev/null 2>&1 || true
  rm -rf "$ws"
}
trap cleanup EXIT

# pass, fail, and $container: the current container, set by `up`, which fail dumps.
# shellcheck source=images/smoke-lib.sh
source "$here/../smoke-lib.sh"
# Commands run the way an attached editor runs them: through the devcontainer CLI, as the remote user.
in_devcontainer() { devcontainer exec --workspace-folder "$ws" "$@"; }

# Write devcontainer.json: the README's privileged-mode snippet (the jsonc block after its
# `smoke-test: privileged` marker), naming the image under test, plus any extra top-level fields.
write_config() {
  local extra="${1:-}"
  awk '/<!-- smoke-test: privileged -->/ { m = 1; next }
       m && /^```/ { if (in_block) exit; in_block = 1; next }
       in_block' "$readme" |
    sed -E "s|\"image\": *\"[^\"]*\"|\"image\": \"$image\"|" >"$config"
  grep -q "\"image\": \"$image\"" "$config" || fail "no privileged-mode snippet with an image in the README"
  if [ -n "$extra" ]; then
    # A top-level field before the closing brace of the snippet.
    sed -i -E '$!b; s|^\}|,'"$extra"'\n}|' "$config"
  fi
}

# Bring the container up, removing an existing one: `up` again is a rebuild.
up() {
  local out status=0 state
  out=$(devcontainer up --workspace-folder "$ws" --remove-existing-container 2>"$ws/up.log" | tail -n1) || status=$?
  container=$(devcontainer_ids | head -n1)
  [ "$status" = 0 ] || { tail -n 40 "$ws/up.log" >&2; fail "devcontainer up failed: $out"; }
  record_volumes
  [ "$(jq -r .outcome <<<"$out")" = success ] || { tail -n 40 "$ws/up.log" >&2; fail "devcontainer up: $out"; }
  [ "$(jq -r .remoteUser <<<"$out")" = dev ] || fail "the remote user is $(jq -r .remoteUser <<<"$out"), not dev"
  state=$(wait_system_running in_devcontainer)
  [ "$state" = running ] || fail "system state after up is '$state', not running"
}

# The label is the image's whole addition: exactly the remote user, the Claude Code extension and
# overrideCommand false. No lifecycle commands, no mounts.
label=$(docker image inspect -f '{{index .Config.Labels "devcontainer.metadata"}}' "$image")
jq -e '. == [{"remoteUser": "dev", "overrideCommand": false,
              "customizations": {"vscode": {"extensions": ["anthropic.claude-code"]}}}]' <<<"$label" >/dev/null ||
  fail "the devcontainer metadata label is not exactly remote user, extension and overrideCommand: $label"
pass "the metadata label carries exactly the remote user, the Claude Code extension and overrideCommand false"

write_config
merged=$(devcontainer read-configuration --workspace-folder "$ws" --include-merged-configuration 2>/dev/null)
jq -e '.mergedConfiguration.customizations.vscode[].extensions | index("anthropic.claude-code")' <<<"$merged" >/dev/null ||
  fail "the merged configuration does not install the Claude Code extension"
pass "the devcontainer CLI reads the Claude Code extension from the image"

up
pass "the devcontainer CLI brings the image up from the README's privileged-mode snippet"

[ "$(in_devcontainer ps -o comm= -p 1)" = systemd ] || fail "PID 1 is not systemd"
pass "systemd is PID 1"

[ "$(in_devcontainer id -un)" = dev ] || fail "commands run as $(in_devcontainer id -un), not dev"
pass "the remote user is dev"

in_devcontainer docker pull -q hello-world >/dev/null
in_devcontainer docker run --rm hello-world | grep -q 'Hello from Docker!' || fail "a container did not run"
pass "Docker runs a container"

in_devcontainer bash -c 'echo survives > ~/marker'
up
[ "$(in_devcontainer cat /home/dev/marker)" = survives ] || fail "a file written to home did not survive a rebuild"
pass "a file written to home survives a rebuild"

# A Feature without an entrypoint on top (Features that start daemons clash with systemd).
write_config '"features": {"ghcr.io/devcontainers/features/github-cli:1": {}}'
up
[ "$(in_devcontainer ps -o comm= -p 1)" = systemd ] || fail "PID 1 is not systemd with a Feature on top"
docker inspect -f '{{index .Config.Labels "devcontainer.metadata"}}' "$container" | grep -q 'github-cli' ||
  fail "the Feature was not applied"
pass "a devcontainer Feature can be added on top and the container still comes up"

# With no mounts at all, the engine still runs containers: its storage is the image's declared volumes (anonymous
# ones, which `up` records for the cleanup).
printf '{"image": "%s", "privileged": true}\n' "$image" >"$config"
up
in_devcontainer docker run --rm hello-world | grep -q 'Hello from Docker!' || fail "a container did not run without mounts"
pass "Docker runs a container in a dev container with no mounts"

echo "devcontainer-base smoke test passed: $image"
