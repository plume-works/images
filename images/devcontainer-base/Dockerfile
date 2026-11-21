# Devcontainer base image: the core systemd image plus a devcontainer metadata label, and nothing else.
# A repository names it in the `image` field of its devcontainer.json; docs/usage/devcontainer-base.md gives the snippets.
# CI (../docker-bake.hcl) always builds on this commit's core systemd image; the default serves plain local builds.
ARG BASE_IMAGE=ghcr.io/plume-works/core-systemd:edge
FROM ${BASE_IMAGE}

# Merged under the consumer's devcontainer.json. overrideCommand false keeps systemd as PID 1 (otherwise the
# editor's own keep-alive command replaces it).
# No lifecycle commands and no mounts: the volumes are the consumer's choice (see docs/usage/devcontainer-base.md).
LABEL devcontainer.metadata='[{"remoteUser":"dev","overrideCommand":false,"customizations":{"vscode":{"extensions":["anthropic.claude-code"]}}}]'
