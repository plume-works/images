# Build the core image first, not the devcontainer

The core image holding the tools comes first, and every other image here is built on it: the core systemd image, then
the Coder template image and the devcontainer base image.

## Considered options

- **Devcontainer first.** Rejected: the predecessor repository (`plume-works/agent-devcontainer`) started there and
  that caused a mess.
