# Renovate keeps pins current, after a 3-day wait

The old repo had Renovate for upkeep and this one needs the same. Updates merge
on their own once the build passes, but only when the release is 3 days old,
because the build cannot tell a bad release from a good one.

Not chosen:

- No wait.
- A wait for the npm-registry tools only.
