# Repositories on the Coder template: bringing their own setup, and keeping installs across restarts

Research done 23–24 November 2026 in an `agent-devcontainer` session, after that repository moved onto these images
(its PR #981). Findings are as of Coder v2.37.1 on a sysbox host, with the Coder template image at
`edge@sha256:dfef91b9…`.

## Initial problem

Once `agent-devcontainer` was moved onto the devcontainer base image, it no longer had a way to run on Coder:

- `agentdev-runtime coder start` had been removed on purpose (agentdev ADR-0107). It used to start OpenCode and
  Claude remote control inside an agentdev dev container that Coder ran, and it was where setup that needed Coder
  secrets ran.
- In this repository, agent services exist only in the Coder template image, and the devcontainer base image is
  for an attached editor only. Running a dev container under Coder falls between the two images, and fixing that
  felt like putting the two images back together.

So the question changed from "how do I run agentdev on Coder" to: **taking the Coder template and its no-bloat
policy as the foundation, how can a repository bring its own tools, plugins and services?** It then narrowed to
**can a workspace keep system-level installs across restarts, with a way to rebuild?** User-level tools are the
common case, but system-level ones (apt packages, root services) are needed too.

## Methodology

1. **Inventory** of `agent-devcontainer`, read from its tree, Dockerfile and runtime CLI, set next to this
   repository's images, to find what overlaps and what belongs to neither image.
2. **Desk analysis** of the Coder template (`templates/coder/main.tf`, the Coder template image's units) and this
   repository's ADRs, listing every way a repository could bring tools, plugins and services, and what each would
   cost the template.
3. **Comparison of mise and pyinfra**, as the user-level and system-level candidates for a repository's own setup,
   against ADRs 0012, 0013, 0014 and 0022. Desk only; nothing was run.
4. **Spikes on the real Coder deployment** for the three ways to keep installs across restarts. Each was a scratch
   template and workspace. Each was checked with a root-owned file in `/opt` and an apt-installed package, plus an
   image pulled into the inner Docker engine for shape 2, then restarted and stopped/started. The scratch templates,
   workspaces and cache images were deleted afterwards. Existing workspaces were not touched.

## Findings

### What `agent-devcontainer` holds, and where it overlaps

- **Not tied to any runtime:** the agentdev plugin catalog (skills and agents), its validator `validate_agent_files`,
  and the IWE knowledge base.
- **Devcontainer only:** the image's additions (Xpra, Playwright, pinned linters, the egress firewall, the `gh`
  wrapper) and the dev container lifecycle part of `agentdev_runtime`.
- **Overlaps with the Coder template image:** setting up an agent in a home directory. `agentdev_runtime` does
  Claude pre-approval, policy, catalog registration and trust. The Coder template image does its own Claude
  pre-approval and Claude default settings. This bucket belongs to neither image. Whether the two write the same
  things was not checked.
- Claude Code and OpenCode are already in the core image. Moving to the devcontainer base image dropped the agent
  services and the Coder wiring, not the agents.

### Ways a repository can bring things along

Today the Coder template's startup script clones the repository, hands the environment to systemd and starts the
agent services. Nothing runs anything from the repository after the clone.

| Kind | Way | Needs a template change? | Notes |
|---|---|---|---|
| Tools | Lockfile-driven and project-local (`uv sync`, `bun install`, pre-commit's own environments) | No, but something must run it | Pinned. Nothing goes on `PATH` from home. Covers only what ships on PyPI or npm. |
| Tools | Containers on the workspace's own engine (`docker run`, compose, pre-commit `docker_image`) | No | Pinned by digest. Slower. Files are owned by the container's user. |
| Tools | A repository image built `FROM` the Coder template image | Yes: the template must accept an image | Heavy. One template version per image. |
| Tools | A version manager (mise, devbox, nix) | Yes: it goes into the image | Conflicts with ADR 0012 unless set up carefully. |
| Plugins | Committed in the repository (`.claude/skills`, `.claude/agents`, `.mcp.json`, `opencode.json`) | No | Native to both agents. ADR 0016 already approves the MCP servers. |
| Plugins | Project-scope `.claude/settings.json` with `extraKnownMarketplaces` and `enabledPlugins` | No | Claude default settings overwrite only the user-scope file. Not verified: whether the plugins install without a prompt on a first run or under remote control. |
| Plugins | Workspace-wide, through Claude default settings | Yes | The bloat this repository's policy rejects. |
| Services | A compose file in the repository, on the workspace's engine | No, but something must start it | Natural home for databases and the like. |
| Services | systemd user units shipped by the repository | Yes: a startup step | Same supervision as the agent services. Runs repository code at boot. |
| Services | A dev container inside the workspace | No | Brings back the nesting and the Coder-secrets gap. |

Most rows need "something to run it", so the design question is a single step in the startup script, between the
clone and the agent services. The options found: no step (the user or an agent runs setup), a convention file that
runs if present (for example `.coder/setup`), or reusing `devcontainer.json` lifecycle fields without a container.
No option was chosen.

### mise compared with pyinfra

They solve different problems and don't compete.

| | mise | pyinfra |
|---|---|---|
| Is | A per-repository tool version manager, with environment variables and tasks | Infrastructure as code in Python, in Ansible's class |
| Installs | Language runtimes and CLI binaries (GitHub releases, aqua with checksums, npm, pipx, cargo) | Anything: apt packages, files in `/etc`, systemd units, users |
| Runs as | The workspace user | Root, through sudo |
| After a restart | Kept, in home | Lost (ADR 0014: only home survives), so it runs again at every start |
| Services | No, only tasks | Yes |
| Trust | `mise trust` for each repository config | None: it is code that runs |

- mise is in direct tension with ADR 0012 (nothing under home on `PATH`). It works by putting per-user installs on
  `PATH`. With versions pinned in the repository, the shadowing is intended rather than stale, but that is still a
  decision to make.
- pyinfra is in tension with ADRs 0013 and 0022: it changes the system at every boot, and is only as pinned as its
  script.
- Not checked: how mature `mise.lock` is for checksums across backends, and whether each of agentdev's linters can
  be fetched by mise.

### Keeping system-level installs across restarts

**Facts that hold for every shape:**

- **The Coder agent token changes on every build** (start, stop, restart), but the agent's ID doesn't. Anything kept
  must receive the new token on every start.
- **The provisioner can control the host's Docker engine.** It runs in the `coderd` container as a user in the group
  that owns the host's Docker socket. It has no Docker CLI, but it has `curl`, so a Terraform `local-exec` can call
  the Docker API directly. It can also download from GitHub.

All three shapes worked:

| | 1. Keep the container | 2. Commit on stop | 3. Build a per-repository image |
|---|---|---|---|
| How | The container is created stopped and not counted on `start_count`. On every build, the provisioner writes the new token and init script into it through the Docker API, then starts it. A stop build stops it. | When the container is destroyed, the provisioner stops and commits it, and the next start runs from that commit. | The provisioner sends the repository's build context to the Docker API's build endpoint. The Docker provider can't do this itself, because it reads the build context at plan time. |
| Kept across a restart | Everything outside home, inner engine storage included | Everything, inner engine images included | Only what the build installs |
| Agent token | Written into the stopped container before each start | Normal (a new container) | Normal |
| Restart cost | Stop and start, about 5 s | Commit and recreate, 2–6 s | Cached build about 1 s; one changed step about 3 s; the first build at full cost (49 s in the spike) |
| Rebuild | Changing a `generation` parameter replaced the container | Changing `generation` started again from the Coder template image | Change the Dockerfile; only the changed steps rebuild |
| Limits found | Terraform doesn't see what happens inside the container | One more image layer per restart. The Coder template image has 29 layers and Docker allows about 125, so about 95 restarts before it breaks without squashing. Old, expired agent tokens stay in the cache images. | Changes made by hand outside home are still lost. The repository's files reach the build through the provisioner (a public GitHub tarball download worked). |

**Gotchas, all seen in the spikes:**

- `coder restart --parameter` and `coder start --parameter` did not change an existing mutable parameter. A build
  created through the API with `rich_parameter_values` did. The web UI's parameter page was not tried.
- A `local-exec` with the agent token in its environment has all its output hidden by Terraform, because the token
  is sensitive. Logging only `nonsensitive(sha256(...))` of it worked.

**Not tested:** private repositories in shape 3 (the plan was a `coder_external_auth` token); an update of the Coder
template image under shapes 1 and 2 (expected to replace the container, since the image ID changes); disk growth
from committed inner engine storage in shape 2.

**How the shapes match the two needs:**

- User-level tools persist in home in every shape, as they do today.
- System-level: shapes 1 and 2 keep whatever happens in the container, including setup the repository runs at
  start (mise, pyinfra or plain apt), so they pair with a runtime setup step. Shape 3 keeps only what is written down
  as a build, so it pairs with a repository Dockerfile.

## Relation to existing decisions

- **ADR 0014** says a restart loses the inner engine's storage, because each start replaces the container. Shapes 1
  and 2 keep that storage without any volume, so they avoid the failure that ADR describes, but they would change its
  consequence. Adopting either needs ADR 0014 revisited.
- **ADRs 0013 and 0022** (an image's content is what was built and tested; all inputs pinned): shapes 1 and 2 keep
  state that was never built or tested. Shape 3 is compatible if the repository's Dockerfile pins its inputs.
- **ADR 0012** (nothing under home on `PATH`): in tension with mise, as above.

## Open questions left by the research

- Which shape suits these images, given how each combines with a repository setup step.
- Whether the Coder template should run a repository setup step at all, and in which form.
