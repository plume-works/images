# Run from this folder (images/), where target contexts resolve.
#
# Target name == folder name == GHCR package name (ghcr.io/plume-works/<name>).
#
# To add an image: create <name>/ with a Dockerfile, smoke.sh and a .dockerignore keeping smoke.sh out of
# the build context, add a target below, and append it to the group. A child image starts with `ARG BASE_IMAGE` /
# `FROM ${BASE_IMAGE}` and its target sets
#   args     = { BASE_IMAGE = "parent" }
#   contexts = { parent = "target:<parent-name>" }
# so it is built on this commit's parent straight from the builder, never on a published tag.

variable "REGISTRY" { default = "ghcr.io/plume-works" }
# CI sets PUSH=true when it publishes; the publish job tags the pushed digests.
variable "PUSH" { default = false }
# CI sets linux/amd64 or linux/arm64.
variable "PLATFORM" { default = "" }

# The local :ci tag the smoke scripts use. Set as the docker output's name, not as `tags`: bake would add `tags`
# to the push output too, and a tagged name cannot be pushed by digest.
function "img" {
  params = [name]
  result = "${REGISTRY}/${name}:ci"
}

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
