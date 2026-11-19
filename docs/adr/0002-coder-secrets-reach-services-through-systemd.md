# Coder secrets reach services through systemd's user manager

Coder puts user secrets (such as `GITHUB_TOKEN`) only into the environment of the Coder agent and what the agent launches. systemd starts before the agent, so a service systemd starts on its own never sees them. The predecessor solved this by starting OpenCode and Claude remote control from an agent start command, which left them unsupervised: nothing restarted a server that stopped.

We keep systemd as the only supervisor (ADR 0001) and hand the environment over instead. The startup sequence in a Coder workspace is:

1. Coder starts the container under sysbox with `/sbin/init`. The Coder template uploads only the agent's init script and token.
2. systemd starts Docker and the Coder agent. The agent's unit is part of the Coder template image and runs as the non-root user, whose systemd user manager is already running.
3. Once connected, the agent's startup script clones the workspace's repository if absent, imports every variable in its environment into the user manager (`systemctl --user import-environment $(compgen -e)`), and starts one target.
4. That target pulls in the agent services, which systemd supervises from then on.

The whole environment is imported, not a named list. A named list would mean editing and pushing the Coder template to add a secret; importing everything means a user creates a Coder secret, restarts the workspace, and the services have it. It exposes nothing new: every terminal session in the workspace already has the same environment, and the services run as the same user.

## Consequences

- A new or rotated secret takes effect on workspace restart; running services keep the environment they started with.
- One exception: Claude remote control is kept from three Anthropic token variables (ADR 0003).
- Anything that needs a Coder secret, including the repository clone, runs from the agent's startup script or from a unit under that target, never from a unit started at boot.
