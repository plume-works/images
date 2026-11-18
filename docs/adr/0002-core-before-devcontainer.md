# Build the core image first, not the devcontainer

The old repo started with the devcontainer and that caused a mess, so this one
does not. A shared `core` image holding the tools comes first, and the
devcontainer, the Coder workspace and the service image are each built on it.
