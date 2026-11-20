# Nothing updates itself

An image's content stays what was built and tested: a version changes only through a pull request that passes
the tests, never by a tool updating itself in a running container. Self-update is turned off for Claude Code and
OpenCode in every way into a shell or service:

- the image's `ENV`, for CI job containers and `docker run` or `exec`
- `/etc/environment`, for `su -l` and SSH logins
- `/etc/environment.d`, for services under a systemd user manager
- for Claude Code also `/etc/claude-code/managed-settings.json`, which a user cannot override

The core systemd image masks the OS's periodic update timers for the same reason.
