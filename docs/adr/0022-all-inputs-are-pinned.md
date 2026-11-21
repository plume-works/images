# All inputs are pinned

Every input to an image is pinned, and a pin changes only through a pull request that passes the tests. Ubuntu's
packages come from a dated snapshot of its archive, set in the core image's apt config, and Renovate proposes a
newer snapshot at most once a day. An input that floats cannot be traced: a cached build quietly keeps an old
version, and an uncached one gives new digests every time, so no build could be shown to be unchanged.

## Considered Options

- Apt packages float within the Ubuntu release (the previous rule, in ADR 0013 and the README).
- Pinning each apt package's version: the Ubuntu archive drops superseded versions, so old pins stop installing.

## Consequences

- The images keep the snapshot in apt's config, so `apt-get install` in a container or CI job gets that day's
  versions too, matching the image's own packages, until a newer image.
- Docker's apt repository has no snapshots, so its packages pin their versions, `containerd.io` down to the package
  revision.
- The snapshot bumps without the release wait of [ADR 0019](0019-renovate-release-wait.md): it carries security
  fixes, and Ubuntu's updates have already passed its own testing.
