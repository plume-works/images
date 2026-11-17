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
  context = "core"
  tags    = ["${REGISTRY}/core:${TAG}"]
  output  = ["type=docker"]
}
