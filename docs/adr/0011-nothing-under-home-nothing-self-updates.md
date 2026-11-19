# Nothing under a home directory, nothing updates itself

A home directory is often a volume, and a volume is filled from the image only
once. Anything installed under `/root` or `/home` freezes at that moment and
then shadows every newer image. So `core` installs every tool outside the homes
(they hold only shell start-up files), and user tool directories are not put on
`PATH`.

For the same reason a version changes only through a pull request that passes
the tests, never by a tool updating itself. Self-update is turned off for
Claude Code and OpenCode in three places, so no way into a shell misses it:

- the image's `ENV`, for CI job containers and `docker run` or `exec`
- `/etc/environment`, for `su -l` and SSH logins
- `/etc/claude-code/managed-settings.json`, which a user cannot override

## Considered Options

- Putting `~/.local/bin` and `~/.bun/bin` on `PATH` for `uv tool install` and
  `bun add -g`: a home volume could then shadow the image's tools.
