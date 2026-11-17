# Renovate keeps pins current, after a wait

The old repo had Renovate for upkeep and this one needs the same. Updates merge
on their own once the build passes, but only when the release is 3 days old,
because the build cannot tell a bad release from a good one. An `x.y.0` release
waits 10 days, since those usually have the most bugs.

Not chosen:

- No wait.
- A wait for the npm-registry tools only.
- Skipping `x.y.0` releases entirely.

GHCR gives no publish date, so Renovate would hold `uv` updates forever. Its
version is read from GitHub releases instead, which do have dates; the image
digest follows in a second update with no wait of its own.
