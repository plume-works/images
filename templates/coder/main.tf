terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "2.20.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "4.7.0" # >= 4.6.0 for upload owner, group and permissions
    }
  }
}

locals {
  repo_dir = "/home/dev/${trimsuffix(basename(data.coder_parameter.repo_url.value), ".git")}"

  # The provider reports a missing full name (an empty CODER_WORKSPACE_OWNER_NAME) as "default", not as empty.
  git_name = (
    contains(["", "default"], data.coder_workspace_owner.me.full_name)
    ? data.coder_workspace_owner.me.name
    : data.coder_workspace_owner.me.full_name
  )
  git_email = data.coder_workspace_owner.me.email
}

variable "docker_socket" {
  type        = string
  description = "Docker daemon to create workspaces on (optional; empty means the provisioner's default)"
  default     = ""
}

provider "docker" {
  host = var.docker_socket != "" ? var.docker_socket : null
}

provider "coder" {}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# `order` keeps the form in this file's order, each dependent choice under the one it depends on; without it the
# form sorts by name.
data "coder_parameter" "repo_url" {
  name         = "repo_url"
  order        = 1
  display_name = "Repository URL"
  description  = "Git URL of the repository to clone into /home/dev on first start, for example https://github.com/plume-works/images.git. A private repository needs a GITHUB_TOKEN Coder secret."
  type         = "string"
  mutable      = false
  icon         = "/icon/git.svg"
}

data "coder_parameter" "repo_branch" {
  name         = "repo_branch"
  order        = 2
  display_name = "Repository branch"
  description  = "Branch to check out when the repository is cloned on first start. Empty means the repository's default branch."
  type         = "string"
  default      = ""
  mutable      = false
  icon         = "/icon/git.svg"
}

# Claude pre-approval (ADR 0016): the two choices only. The image acts on them (claude-pre-approval.service).
data "coder_parameter" "claude_remote_control" {
  name         = "claude_remote_control"
  order        = 3
  display_name = "Claude remote control"
  description  = "Workspace-wide (the workspace is the sandbox): grant Claude remote control's one-time consent, so it never waits on that prompt."
  type         = "bool"
  default      = "true"
  mutable      = false
}

data "coder_parameter" "claude_trust_workspace" {
  name         = "claude_trust_workspace"
  order        = 4
  display_name = "Claude trust workspace"
  description  = "Workspace-wide (the workspace is the sandbox): trust the cloned repository in Claude, and approve every project's MCP servers. Switch off for really untrusted code."
  type         = "bool"
  default      = "true"
  mutable      = false
}

# Acted on at each start (claude-repo-plugins.service); off installs nothing new and removes nothing. Offered only
# while the repository is trusted: installing its plugins grants more than trusting it.
data "coder_parameter" "claude_install_repo_plugins" {
  count        = tobool(data.coder_parameter.claude_trust_workspace.value) ? 1 : 0
  name         = "claude_install_repo_plugins"
  order        = 5
  display_name = "Auto-install enabled Claude plugins from repo"
  description  = "At each start, install for you every Claude plugin the repository's .claude/settings.json enables, with the marketplaces it declares."
  type         = "bool"
  default      = "true"
  mutable      = true
}

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  dir  = local.repo_dir

  # In the agent's environment, so in its startup script, every terminal and app, and (through the import below)
  # every agent service.
  env = {
    REPO_URL                          = data.coder_parameter.repo_url.value
    REPO_BRANCH                       = data.coder_parameter.repo_branch.value
    REPO_DIR                          = local.repo_dir
    GIT_AUTHOR_NAME                   = local.git_name
    GIT_AUTHOR_EMAIL                  = local.git_email
    GIT_COMMITTER_NAME                = local.git_name
    GIT_COMMITTER_EMAIL               = local.git_email
    CLAUDE_PREAPPROVE_REMOTE_CONTROL  = data.coder_parameter.claude_remote_control.value
    CLAUDE_PREAPPROVE_TRUST_WORKSPACE = data.coder_parameter.claude_trust_workspace.value
    # Off with trust off, whatever an older build or the command line set it to.
    CLAUDE_INSTALL_REPO_PLUGINS = try(data.coder_parameter.claude_install_repo_plugins[0].value, "false")
  }

  # Runs as dev in bash (compgen is a bash builtin). Coder secrets are in its environment, so the clone can use
  # GITHUB_TOKEN through the image's git credential helper. The whole environment is imported, not a named list,
  # so that a new Coder secret never needs a template change (ADR 0002).
  # A failed clone does not stop the hand-off: the agent services start anyway, and the script then exits non-zero
  # so Coder shows the startup script as failed, with the reason in its log.
  startup_script_behavior = "blocking"
  startup_script          = <<-EOT
    set -eu
    cloned=true
    if [ ! -d "$REPO_DIR/.git" ] && ! git clone $${REPO_BRANCH:+--branch "$REPO_BRANCH"} "$REPO_URL" "$REPO_DIR"; then
      cloned=false
      echo "ERROR: could not clone $REPO_URL$${REPO_BRANCH:+ at branch $REPO_BRANCH} into $REPO_DIR (see git's message above)." >&2
      echo "ERROR: starting the agent services anyway; clone the repository from a terminal." >&2
    fi
    systemctl --user import-environment $(compgen -e)
    systemctl --user start agent-services.target
    [ "$cloned" = true ]
  EOT

  display_apps {
    vscode                 = true
    vscode_insiders        = false
    web_terminal           = true
    ssh_helper             = true
    port_forwarding_helper = true
  }
}

# VS Code in the browser, installed into /tmp at each start (nothing editor-related is in the image).
module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "1.6.0"
  agent_id = coder_agent.main.id
  folder   = local.repo_dir
  # renovate: datasource=github-releases depName=coder/code-server
  install_version = "4.146.0"
}

# OpenCode's server (API and web UI), run by opencode.service on localhost:4096. OpenCode cannot run under a path
# prefix, so this needs a subdomain app, and so a wildcard access URL on the Coder deployment. OpenCode asks for
# its own password on top of Coder's sign-in: the user's OPENCODE_PASSWORD Coder secret (see README.md beside this file).
resource "coder_app" "opencode" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_agent.main.id
  slug         = "opencode"
  display_name = "OpenCode"
  icon         = "/icon/opencode.svg"
  url          = "http://localhost:4096"
  subdomain    = true
  share        = "owner"
  open_in      = "tab"

  # The web shell at / answers 200 without credentials (the API under /api asks for them).
  healthcheck {
    url       = "http://localhost:4096/"
    interval  = 5
    threshold = 6
  }
}

# Kept on the host when a workspace is deleted: other workspaces use it too.
resource "docker_image" "main" {
  # Renovate proposes digest bumps: its terraform manager reads a docker_image name only as a literal string, so
  # keep the reference here, not in a local or variable.
  name         = "ghcr.io/plume-works/coder-template:edge@sha256:6b7ec021f9b216938a6364f9e318d73797e59d82a75df0f4d1494c3015fe676c"
  keep_locally = true
}

# The only state that persists: home. Never replaced or deleted by a template change; deleted with the workspace.
# Nothing is mounted at the inner Docker engine's storage (ADR 0014): sysbox gives each container its own, removed
# with it.
resource "docker_volume" "home" {
  name = "coder-${data.coder_workspace.me.id}-home"
  lifecycle {
    ignore_changes = all
  }
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
}

# Recreated at every start, so everything outside home comes fresh from the image.
resource "docker_container" "workspace" {
  count    = data.coder_workspace.me.start_count
  image    = docker_image.main.image_id
  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = lower(data.coder_workspace.me.name)

  # sysbox only: there is no privileged fallback. Sysbox sets up systemd only when the first argument is exactly
  # /sbin/init.
  runtime    = "sysbox-runc"
  entrypoint = ["/sbin/init"]
  command    = []

  # systemd's shutdown signal, and time for the inner Docker engine to stop its containers.
  stop_signal           = "SIGRTMIN+3"
  destroy_grace_seconds = 60

  # The only two things the template puts into the container; coder-agent.service reads them.
  # A Coder access URL on localhost means the host.
  upload {
    file        = "/etc/coder/agent-init.sh"
    content     = replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")
    permissions = "0755"
  }
  upload {
    file        = "/etc/coder/agent-token"
    content     = coder_agent.main.token
    owner       = "1000"
    group       = "1000"
    permissions = "0600"
  }
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  volumes {
    container_path = "/home/dev"
    volume_name    = docker_volume.home.name
  }


  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
}
