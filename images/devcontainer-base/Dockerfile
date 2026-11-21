# Devcontainer base image: the core systemd image plus a devcontainer metadata label, and nothing else.
# A repository names it in the `image` field of its devcontainer.json; docs/usage/devcontainer-base.md gives the snippets.
# CI (../docker-bake.hcl) always builds on this commit's core systemd image; the default serves plain local builds.
ARG BASE_IMAGE=ghcr.io/plume-works/core-systemd:edge
FROM ${BASE_IMAGE}

# Read by the devcontainer CLI and VS Code, merged under the consumer's devcontainer.json:
# - remoteUser: the editor and its terminals run as dev;
# - overrideCommand false: keep the image's entrypoint, so systemd stays PID 1 (otherwise the
#   editor's own keep-alive command replaces it);
# - the Claude Code VS Code extension.
# No lifecycle commands and no mounts: the volumes are the consumer's choice (see docs/usage/devcontainer-base.md).
LABEL devcontainer.metadata='[{"remoteUser":"dev","overrideCommand":false,"customizations":{"vscode":{"extensions":["anthropic.claude-code"]}}}]'
