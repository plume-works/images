variable "REGISTRY" {
  default = "ghcr.io/plume-works"
}

variable "TAG" {
  default = "edge"
}

group "default" {
  targets = ["core"]
}

target "core" {
  context = "images/core"
  tags    = ["${REGISTRY}/core:${TAG}"]
  output  = ["type=docker"]
  # One plain manifest, so the tested and pushed images compare by manifest digest.
  attest  = ["type=provenance,disabled=true"]
  labels = {
    "org.opencontainers.image.title"       = "core"
    "org.opencontainers.image.description" = "Host-neutral base image with dev tools for plume-works images"
    "org.opencontainers.image.source"      = "https://github.com/plume-works/images"
  }
}
