# One directory per image, wired by a bake file

Each image lives in `images/<name>/` and `docker-bake.hcl` wires them together. An image built on another sees
only its finished parent, so it cannot push its own requirements down into the parent. A new image is a new
directory and a bake target, with no edits to existing images.

## Considered options

- One multi-stage Dockerfile: simplest, but nothing separates the core image from the images built on it.
- Devcontainer Features: would put a devcontainer builder under every image.
