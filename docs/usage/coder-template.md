# Coder template image

`ghcr.io/plume-works/coder-template`: the core systemd image plus the Coder agent and two agent services
(OpenCode's server and Claude remote control), run directly as the workspace container by the **Coder template**
in [`images/coder-template/template/`](../../images/coder-template/template/). It is used only through that
template.

What a workspace gives its users, the Coder secrets they set and their first-time setup are in the
[template's README](../../images/coder-template/template/README.md), which Coder shows on the template's page.
This page is for the administrator of the Coder host.

## Requirements on the Coder deployment

- **[sysbox](https://github.com/nestybox/sysbox) on the Docker host.** There is no privileged fallback: without
  sysbox, every workspace fails to start ([ADR 0001](../adr/0001-docker-engine-under-systemd.md)).
- A Linux Docker host reachable by the provisioner (`docker_socket` template variable, empty for the default).
- A **wildcard access URL** (`CODER_WILDCARD_ACCESS_URL`) for the OpenCode button: OpenCode's web UI cannot run
  under a path prefix, so without wildcards the button does not open.

## Pushing the template

Nothing pushes it automatically. From a clean checkout:

```sh
coder login https://coder.example.com
coder templates push plume-works -d images/coder-template/template -m "<commit or change>" -y
```

The first push creates the template; later pushes add a version and make it active. Its name and description
come from the front matter of the template's README.

`main.tf` pins the image by digest, and Renovate's "plume-works images" pull request moves it as soon as
`edge` moves, merging itself once its checks pass.

## Troubleshooting

- Each agent service runs its app in its own tmux server, named after its unit
  ([ADR 0015](../adr/0015-agent-services-run-inside-tmux.md)). As the workspace user, `ls /tmp/tmux-$(id -u)`
  lists the tmux sockets, among them one per running agent service. To see where one is stuck:
  `tmux -L opencode attach -r` or `tmux -L claude-remote-control attach -r` (read-only, so a stray keystroke cannot
  reach the app; detach with `Ctrl-b d`). Attach without `-r` to answer a prompt the app waits on.
- Logs: `journalctl -u coder-agent` and `journalctl --user -u opencode -u claude-remote-control`. The journal holds
  none of an app's live output, only its last screen (with scrollback) each time it exited.
- A new or rotated Coder secret reaches the services only on workspace restart
  ([ADR 0002](../adr/0002-coder-secrets-reach-services-through-systemd.md)).
- Claude remote control never sees `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN` or `CLAUDE_CODE_OAUTH_TOKEN`, and
  keeps retrying until the user has `/login`ed and the repository is trusted: by Claude pre-approval unless
  switched off at creation, else by running `claude` in it
  ([ADR 0017](../adr/0017-anthropic-tokens-kept-from-remote-control.md),
  [ADR 0016](../adr/0016-claude-pre-approval-on-by-default.md)).
- The Claude pre-approval choices are workspace-wide, because the workspace is the sandbox: only trust names the
  cloned repository; every project's MCP servers in the workspace are approved ([ADR 0016](../adr/0016-claude-pre-approval-on-by-default.md)).
- One volume per workspace persists across rebuilds: `/home/dev`. Everything else is recreated at every start,
  the Docker engine's storage included ([ADR 0014](../adr/0014-no-engine-storage-volumes.md)).
