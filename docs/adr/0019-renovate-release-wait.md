# Renovate keeps pins current, after a wait

Renovate keeps pins current. Updates merge on their own once the build passes, but only when
the release is 3 days old, because the build cannot tell a bad release from a good one.
An `x.y.0` release waits 10 days, since those usually have the most bugs.

Four kinds of pin skip the wait, because their registries do not say when a release was published:

- Our own images bump as soon as `edge` moves. CI has already built and tested them.
- Docker's engine packages bump as soon as Docker's apt repository has them. That repository already
  publishes hours or days after GitHub does.
- Coder's Terraform modules bump as soon as Coder's registry has them. With the wait, Renovate would
  never propose them.
- The Ubuntu archive snapshot bumps as soon as the archive changes, since it carries security fixes
  ([ADR 0022](0022-all-inputs-are-pinned.md)).

## Considered Options

- No wait.
- A wait for the npm-registry tools only.
- Skipping `x.y.0` releases entirely.
- Timing Docker's engine packages by their GitHub releases, which would propose versions apt cannot install yet.
