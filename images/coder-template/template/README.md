---
display_name: plume-works workspace
description: Requires sysbox on the Docker host (no privileged fallback). Clones one repository; runs OpenCode and Claude remote control.
icon: /icon/docker.svg
---

# plume-works workspace

**The Docker host must have [sysbox](https://github.com/nestybox/sysbox) installed.** The workspace container runs
under the `sysbox-runc` runtime with systemd as PID 1; there is no privileged fallback, and without sysbox every
workspace fails to start.

One container per workspace, from `ghcr.io/plume-works/coder-template` pinned by digest, with the repository you
name cloned into `/home/dev/<repository>`. Source and documentation:
[plume-works/images](https://github.com/plume-works/images), `images/coder-template/`.

## What you get

- VS Code Desktop, VS Code in the browser (code-server, version pinned), a web terminal and SSH.
- **OpenCode**: its web UI, opened by the OpenCode button, for you only. It needs a wildcard access URL on the
  Coder deployment.
- **Claude remote control** in worktree mode on your repository: each remote session gets its own worktree.
- A Docker engine of your own inside the workspace.
- Git commits under the name and email of your Coder account.

Both agent services are supervised by systemd and restarted whenever they stop. Logs:
`journalctl --user -u opencode -u claude-remote-control`, and `journalctl -u coder-agent` for the agent.

## Coder secrets

Every Coder secret you define reaches your terminals and both agent services; a new or changed secret takes effect
when you restart the workspace. Useful ones:

- `GITHUB_TOKEN`: `git clone`, `git push` and `gh` use it with no setup. Needed to clone a private repository.
- `OPENCODE_PASSWORD`: the password OpenCode's web UI asks for (user `opencode`), on top of your Coder sign-in.
  Without it, OpenCode makes up a new one at every start; find it with
  `journalctl --user -u opencode | grep password`.
- Do not use `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN` or `CLAUDE_CODE_OAUTH_TOKEN` for Claude remote control:
  it needs a claude.ai subscription sign-in, and they are kept away from it.

## First-time setup

Run `claude` in the repository, accept the trust prompt, and `/login` with your claude.ai subscription. Remote
control starts on its own within 15 seconds. You do this once: sign-ins live in your home directory.

## What survives

Your home directory (the checkout, agent sign-ins, shell history) and the Docker engine's images, containers and
volumes persist for the life of the workspace. Everything else comes fresh from the image at every start. The
repository is cloned only if `/home/dev/<repository>` has no checkout yet; the URL cannot be changed later.
If the clone fails (a private repository without `GITHUB_TOKEN`, say), the workspace still starts and the startup
script's log says why; clone it into `/home/dev/<repository>` from a terminal and the agent services pick it up.
