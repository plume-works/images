# All inputs are pinned

Every input to an image is pinned, and a pin changes only through a pull request that passes the tests. That
includes Ubuntu's packages, which come from a dated snapshot of the Ubuntu archive. An input that floats cannot be
traced: a cached build quietly keeps an old version, and an uncached one gives new digests every time, so no build
could be shown to be unchanged.

## Considered Options

- Apt packages float within the Ubuntu release (the previous rule, in ADR 0013 and the README).
- Pinning each apt package's version: the Ubuntu archive drops superseded versions, so old pins stop installing.

## Consequences

- Packages installed later, in a container or CI job running an image, come from the image's snapshot too,
  matching the image's own packages, until a newer image.
- Docker's apt repository has no snapshots, so each of its packages is pinned on its own.
- The snapshot skips the release wait of [ADR 0019](0019-renovate-release-wait.md): it carries security fixes,
  and Ubuntu's updates have already passed its own testing.
