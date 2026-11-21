# Nothing under a home directory

A home directory is often a volume, and a volume is filled from the image only once. Anything installed under
`/root` or `/home` freezes at that moment and then shadows every newer image. So the core image installs every
tool outside the homes (they hold only shell start-up files), and user tool directories are not put on `PATH`.

## Considered options

- Putting `~/.local/bin` and `~/.bun/bin` on `PATH` for `uv tool install` and `bun add -g`: a home volume could
  then shadow the image's tools.
