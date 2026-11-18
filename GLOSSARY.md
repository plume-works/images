# Images

Container images published by plume-works for running and developing software with coding agents.

## Language

**Core image**:
An image holding development toolchains, a Docker engine and the Claude Code and OpenCode command-line tools, used directly by CI jobs and as the parent of every other image here.
_Avoid_: Tools image, base image, CI image

**Coder template image**:
The image a Coder template runs directly as its workspace container, adding to the core image what a long-running workspace needs.
_Avoid_: Workspace image, deploy image

**Coder template**:
The Coder workspace definition that runs the Coder template image, kept in this repository beside the image it is coupled to.
_Avoid_: Workspace template

**Devcontainer base image**:
The image a repository's `devcontainer.json` names for a dev container opened from local VS Code, adding to the core image what an attached editor needs.
_Avoid_: Devcontainer image, devcontainer runtime
