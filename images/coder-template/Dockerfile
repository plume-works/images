# CI (../docker-bake.hcl) always builds on this commit's core systemd image; the default serves plain local builds.
ARG BASE_IMAGE=ghcr.io/plume-works/core-systemd:edge
FROM ${BASE_IMAGE}

COPY coder-agent/coder-agent.service /etc/systemd/system/
RUN install -d -m0755 /etc/coder \
 && systemctl enable coder-agent.service

# Nothing enables these user units; only the Coder agent's startup script starts the target (ADR 0002).
COPY agent-services/agent-services.target opencode/*.service claude/*.service /etc/systemd/user/
COPY --chmod=0755 agent-services/run-in-tmux claude/claude-pre-approval claude/claude-repo-plugins /usr/local/bin/
COPY --chmod=0755 claude/claude-bridge-prompt-scrub /usr/local/libexec/
COPY claude/claude-default-settings.json /usr/local/share/claude-code/default-settings.json
