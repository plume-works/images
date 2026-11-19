# Renovate keeps pins current, after a wait

The old repo had Renovate for upkeep and this one needs the same. Updates merge
on their own once the build passes, but only when the release is 3 days old,
because the build cannot tell a bad release from a good one. An `x.y.0` release
waits 10 days, since those usually have the most bugs.

`uv` and OpenCode take their versions from GitHub releases, which carry publish
dates, so the wait applies to them like every other tool.

## Considered Options

- No wait.
- A wait for the npm-registry tools only.
- Skipping `x.y.0` releases entirely.
