# One directory per image, wired by a bake file

Each image built on `core` can only see the finished core image, so it cannot
push its own requirements down into the core. A new image is a new directory,
with no edits to existing ones.

Not chosen:

- One multi-stage Dockerfile: simplest, but nothing separates core from the
  images built on it.
- Devcontainer Features: would put a devcontainer builder under every image.
