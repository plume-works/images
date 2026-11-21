# Coder secrets reach services through systemd's user manager

Coder puts user secrets (such as `GITHUB_TOKEN`) only into the environment of the Coder agent, and systemd starts before the agent, so services systemd starts on its own never see them. We keep systemd as the only supervisor (ADR 0001): once connected, the agent's startup script imports its whole environment into the non-root user's systemd user manager and only then starts the agent services, which systemd supervises from then on.

Importing the whole environment means a user creates a Coder secret, restarts the workspace, and the services have it. It exposes nothing new: every terminal session in the workspace already has the same environment, and the services run as the same user.

## Considered options

- **Start the services from the agent's start command**, as the predecessor did. Rejected: it leaves them unsupervised, so nothing restarts a server that stops.
- **Import a named list of variables.** Rejected: adding a secret would mean editing and pushing the Coder template.

## Consequences

- A new or rotated secret takes effect on workspace restart; running services keep the environment they started with.
- One exception: Claude remote control is kept from the Anthropic token variables that stop it (ADR 0003).
- Anything that needs a Coder secret, including the repository clone, runs from the agent's startup script or from a service it starts, never from a unit started at boot.
