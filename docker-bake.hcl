# Every image of this repository, built from one commit.
#
# Target name == folder under images/ == GHCR package name (ghcr.io/plume-works/<name>).
# The "default" group lists the images parent first; CI smoke-tests them in that order.
#
# To add an image: create images/<name>/ with a Dockerfile and smoke.sh, add a target below, and append it
# to the group. A child image starts with `ARG BASE_IMAGE` / `FROM ${BASE_IMAGE}` and its target sets
#   args     = { BASE_IMAGE = "parent" }
#   contexts = { parent = "target:<parent-name>" }
# so it is built on this commit's parent straight from the builder, never on a published tag.
#
# Local use: `docker buildx bake --load`, then `images/<name>/smoke.sh ghcr.io/plume-works/<name>:ci`.

variable "REGISTRY" { default = "ghcr.io/plume-works" }
# CI sets PUSH=true for the second, publishing pass (a cache hit, so the pushed bits are the tested bits).
variable "PUSH" { default = false }
# CI sets linux/amd64 or linux/arm64; empty means the builder's native platform.
variable "PLATFORM" { default = "" }

function "img" {
  params = [name]
  # Test pass: a local :ci tag the smoke scripts use. Publish pass: the bare repository, pushed by digest.
  result = PUSH ? "${REGISTRY}/${name}" : "${REGISTRY}/${name}:ci"
}

function "out" {
  params = []
  result = PUSH ? ["type=image,push-by-digest=true,name-canonical=true,push=true"] : ["type=docker"]
}

group "default" {
  targets = ["core", "core-systemd", "devcontainer-base"]
}

target "_common" {
  platforms = PLATFORM == "" ? [] : [PLATFORM]
  output    = out()
  labels    = { "org.opencontainers.image.source" = "https://github.com/plume-works/images" }
}

target "core" {
  inherits = ["_common"]
  context  = "images/core"
  tags     = [img("core")]
}

target "core-systemd" {
  inherits = ["_common"]
  context  = "images/core-systemd"
  args     = { BASE_IMAGE = "parent" }
  contexts = { parent = "target:core" }
  tags     = [img("core-systemd")]
}

target "devcontainer-base" {
  inherits = ["_common"]
  context  = "images/devcontainer-base"
  args     = { BASE_IMAGE = "parent" }
  contexts = { parent = "target:core-systemd" }
  tags     = [img("devcontainer-base")]
}
