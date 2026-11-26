# mise for the tools the image does not carry

The core image ships mise, so a repository can declare the tools its work needs beyond the image's in its
`mise.toml`, and anyone using the image can install them. mise is admitted outside the core image's admission
rule: it is how a repository brings the tools that rule keeps out. The image's own tools are not installed through
mise, and the image does not activate it: what a user installs with mise is theirs, kept in their home and off
`PATH` until they turn mise on ([ADR 0012](0012-nothing-under-home.md)). mise does not update itself
([ADR 0013](0013-nothing-updates-itself.md)).

## Considered Options

- Installing the image's own tools through mise as well. Only some of them could move, so there would be two ways
  of installing instead of one. A repository's `mise.toml` would also quietly change the image's
  tested tools.
- Shrinking the core image to a bare base and leaving every toolchain to mise. Every CI job would then install
  its toolchain before it could start, and CI, workspaces and dev containers would no longer share one tested
  toolchain.
- Activating mise system-wide, so the tools a user installs are on everyone's `PATH`. A home volume could then
  shadow the image's tools.
