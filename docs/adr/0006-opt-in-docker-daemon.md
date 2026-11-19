# The Docker daemon is opt-in, and core has no entrypoint

`core` installs the Docker engine and one script, `start-docker`, that nothing
calls by default. An image that wants Docker calls it from its own startup, so
the daemon logic exists once and images that don't need Docker don't have to
run privileged.

## Considered Options

- Binaries only: each image would write its own daemon startup.
- An entrypoint in core that starts the daemon: every image would inherit it
  and have to run privileged. This is what the old repo did.
