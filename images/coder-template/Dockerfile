# Coder template image: the core systemd image plus the Coder agent unit and the agent services, and nothing
# else. The Coder template in this folder runs it directly as the workspace container, under sysbox.
# The hand-off between the template and these units is described in ADR 0002 (docs/adr/).
# CI (docker-bake.hcl) always builds on this commit's core systemd image; the default serves plain local builds.
ARG BASE_IMAGE=ghcr.io/plume-works/core-systemd:edge
FROM ${BASE_IMAGE}

# The Coder agent runs as dev from boot, once the template has uploaded its init script and token to
# /etc/coder (the directory is created here; the files are not).
COPY coder-agent.service /etc/systemd/system/
RUN install -d -m0755 /etc/coder \
 && systemctl enable coder-agent.service

# The agent services and Claude pre-approval: user units for dev's user manager, pulled in by
# agent-services.target. Nothing enables them; only the Coder agent's startup script starts the target (ADR 0002).
COPY agent-services.target opencode.service claude-pre-approval.service claude-remote-control.service /etc/systemd/user/
COPY --chmod=0755 claude-pre-approval /usr/local/bin/claude-pre-approval
