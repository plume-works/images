# Renovate runs in Actions, and archive hashes are baked into the Dockerfile

`uv` and OpenCode are installed from GitHub release archives, and each archive
is checked against a sha256 committed in the Dockerfile. A checksum fetched
from the same server at build time protects against nothing: whoever swaps the
archive swaps the checksum. The build fails when the bytes do not match.

Renovate therefore runs in a workflow, as the `plume-works-renovate` GitHub
App, so that a post-upgrade script (`scripts/bake_hashes.py`) can refill the
hashes in the same commit as the version. The script takes the hash GitHub
recorded for each Linux archive and refuses a release that is not immutable, so
a failed run leaves a branch that cannot pass its build and nothing merges.

This reverses issue 4, which asked for the hosted Renovate app and no custom
pinning scripts. The hosted app cannot run a script.

Two exceptions are deliberate:

- Vendor apt repos (gh, Docker) fetch their signing key at build time, as apt
  rules have it, and float.
- Claude Code from npm has no hash here. Its exact version and the 3-day wait
  of ADR-0009 are the protection. npm never lets a `package@version` be
  published twice, so an exact version cannot be swapped for other bytes, and
  a version can be unpublished freely only in its first 72 hours, which the
  3-day wait outlasts. After that, a package as widely used as Claude Code
  cannot be unpublished
  ([npm unpublish policy](https://docs.npmjs.com/policies/unpublish)).

## Considered Options

- PR 18's approach, downloading the archive and its checksum from the same
  server: no protection against a swapped binary or a man in the middle.
- The hosted Renovate app: cannot run the post-upgrade script.
