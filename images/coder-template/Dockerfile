# CI (../docker-bake.hcl) always builds on this commit's core systemd image; the default serves plain local builds.
ARG BASE_IMAGE=ghcr.io/plume-works/core-systemd:edge
FROM ${BASE_IMAGE}

COPY coder-agent.service /etc/systemd/system/
RUN install -d -m0755 /etc/coder \
 && systemctl enable coder-agent.service

# Nothing enables these user units; only the Coder agent's startup script starts the target (ADR 0002).
COPY agent-services.target opencode.service claude-setup.service claude-remote-control.service \
     claude-bridge-prompt-scrub.service /etc/systemd/user/
COPY claude-default-settings.json /usr/local/share/claude-code/default-settings.json
COPY --chmod=0755 claude-pre-approval claude-repo-plugins run-in-tmux /usr/local/bin/
COPY --chmod=0755 claude-bridge-prompt-scrub /usr/local/libexec/
