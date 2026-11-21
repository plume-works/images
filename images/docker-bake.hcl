# Every image of this repository, built from one commit.
#
# Run from this folder (images/), where target contexts resolve.
#
# Target name == folder name == GHCR package name (ghcr.io/plume-works/<name>).
# The "default" group lists every image. CI works on them parent first, in the order .github/scripts/images.sh
# derives from each target's `contexts` parent link (`bake --print` sorts the group by name, so its order is not it).
#
# To add an image: create <name>/ with a Dockerfile, smoke.sh and a .dockerignore keeping smoke.sh out of
# the build context, add a target below, and append it to the group. A child image starts with `ARG BASE_IMAGE` /
# `FROM ${BASE_IMAGE}` and its target sets
#   args     = { BASE_IMAGE = "parent" }
#   contexts = { parent = "target:<parent-name>" }
# so it is built on this commit's parent straight from the builder, never on a published tag.
#
# Local use: `docker buildx bake`, then `<name>/smoke.sh ghcr.io/plume-works/<name>:ci`.

variable "REGISTRY" { default = "ghcr.io/plume-works" }
# CI sets PUSH=true when it publishes. The one build then also pushes each image by digest, untagged, alongside
# loading it for the smoke tests: one build, two outputs, so the pushed bits are the tested bits by construction.
# Nothing is tagged here; the publish job tags the digests only after every smoke test on both architectures passed.
variable "PUSH" { default = false }
# CI sets linux/amd64 or linux/arm64; empty means the builder's native platform.
variable "PLATFORM" { default = "" }

# The local :ci tag the smoke scripts use. Set as the docker output's name, not as `tags`: bake would add `tags`
# to the push output too, and a tagged name cannot be pushed by digest.
function "img" {
  params = [name]
  result = "${REGISTRY}/${name}:ci"
}

# Always load into the local engine for the smoke tests; with PUSH, also push the same build by digest.
function "out" {
  params = [name]
  result = concat(
    ["type=docker,name=${img(name)}"],
    PUSH ? ["type=image,name=${REGISTRY}/${name},push-by-digest=true,name-canonical=true,push=true"] : []
  )
}

group "default" {
  targets = ["core", "core-systemd", "coder-template", "devcontainer-base"]
}

target "_common" {
  platforms = PLATFORM == "" ? [] : [PLATFORM]
  labels    = { "org.opencontainers.image.source" = "https://github.com/plume-works/images" }
}

target "core" {
  inherits = ["_common"]
  context  = "core"
  output   = out("core")
}

target "core-systemd" {
  inherits = ["_common"]
  context  = "core-systemd"
  args     = { BASE_IMAGE = "parent" }
  contexts = { parent = "target:core" }
  output   = out("core-systemd")
}

target "coder-template" {
  inherits = ["_common"]
  context  = "coder-template"
  args     = { BASE_IMAGE = "parent" }
  contexts = { parent = "target:core-systemd" }
  output   = out("coder-template")
}

target "devcontainer-base" {
  inherits = ["_common"]
  context  = "devcontainer-base"
  args     = { BASE_IMAGE = "parent" }
  contexts = { parent = "target:core-systemd" }
  output   = out("devcontainer-base")
}
