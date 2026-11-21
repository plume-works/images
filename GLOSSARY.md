# Images

Container images published by plume-works for running and developing software with coding agents.

## Language

**Core image**:
An image holding development toolchains, a Docker engine and the Claude Code and OpenCode command-line tools, used directly by CI jobs and as the root every other image here is built on.
_Avoid_: Tools image, base image, CI image

**Core systemd image**:
The core image with systemd as its main process and the Docker engine run as a service, the shared parent of the Coder template image and the devcontainer base image.
_Avoid_: Systemd base, init image

**Coder template image**:
The image a Coder template runs directly as its workspace container, adding to the core systemd image what a long-running workspace needs.
_Avoid_: Workspace image, deploy image

**Coder template**:
The Coder workspace definition that runs the Coder template image, kept in this repository beside the image it is coupled to.
_Avoid_: Workspace template

**Devcontainer base image**:
The image a repository's `devcontainer.json` names for a dev container opened from local VS Code, adding to the core systemd image what an attached editor needs.
_Avoid_: Devcontainer image, devcontainer runtime

**Agent service**:
A long-running app (such as OpenCode's server or Claude remote control) that the Coder template image runs for the workspace user once the Coder agent has handed over its environment.
_Avoid_: User service, background agent

**Claude pre-approval**:
Answering Claude Code's first-run questions for the workspace user before Claude Code asks them: its onboarding.
_Avoid_: Seeding, auto-trust
