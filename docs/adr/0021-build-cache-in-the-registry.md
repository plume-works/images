# Build cache in the registry

CI caches every build step of each image, separately for each architecture, in the image's own GHCR package
beside its tags. Every CI run reads and writes it, pull requests and `main` alike. Local builds do not use it.

## Considered Options

- No cache: every run rebuilds every image from scratch.
- The GitHub Actions cache: capped in size, evicts, and is scoped per branch.
- A separate cache package per image: more packages to manage, for no gain.

## Consequences

- The cache tags are visible in each image's package.
- A superseded cache stays as an untagged version, like the other untagged images the cleanup keeps.
- Pull requests and `main` share one cache per image and architecture, so each overwrites the other's.
