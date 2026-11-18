# Images

Container images published by plume-works for running and developing software with coding agents.

## Language

**Core image**:
An image holding development toolchains and a Docker engine, with no agents, used directly by CI jobs and as the parent of every other image here.
_Avoid_: Tools image, base image, CI image

**Coder template image**:
The image a Coder template runs directly as its workspace container, with Claude Code and OpenCode installed.
_Avoid_: Workspace image, deploy image

**Coder template**:
The Coder workspace definition that runs the Coder template image, kept in this repository beside the image it is coupled to.
_Avoid_: Workspace template

**Devcontainer base image**:
The image a repository's `devcontainer.json` names for a dev container opened from local VS Code, with Claude Code and OpenCode installed.
_Avoid_: Devcontainer image, devcontainer runtime
