# Build the core image first, not the devcontainer

The predecessor repository (`plume-works/agent-devcontainer`) started with the devcontainer and that caused a
mess, so this one does not. The core image holding the tools comes first, and every other image here is built on
it: the core systemd image, then the Coder template image and the devcontainer base image.
