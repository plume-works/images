# Nothing updates itself

An image's content stays what was built and tested: nothing in a running container updates itself, and a pinned
version changes only through a pull request that passes the tests. Self-update is turned off for Claude Code and
OpenCode however a shell or service is started, and for Claude Code also in a way a user cannot override. The
core systemd image turns off the OS's periodic updates for the same reason.

## Consequences

- Apt packages are the exception to pinning: they float within the Ubuntu release, so a rebuild can pick up
  newer ones, but only through a build that passes the same tests.
