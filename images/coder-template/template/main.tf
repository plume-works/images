# The Coder template: one workspace container, run directly from the Coder template image under sysbox.
#
# How a workspace starts (ADR 0002): systemd boots as PID 1, its coder-agent.service runs the init script uploaded
# below, and the agent's startup script clones the repository, hands its whole environment to dev's systemd user
# manager and starts agent-services.target (OpenCode server and Claude remote control). The image's side of this
# contract is in images/coder-template/ (the units) and docs/adr/0002.
#
# REQUIRES SYSBOX on the Docker host (runtime sysbox-runc). There is no privileged fallback.

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
  # Where the repository is cloned: /home/dev/<repository name>.
  repo_dir = "/home/dev/${trimsuffix(basename(data.coder_parameter.repo_url.value), ".git")}"

  # Git identity from the Coder account.
  git_name  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
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

# The only parameter.
data "coder_parameter" "repo_url" {
  name         = "repo_url"
  display_name = "Repository URL"
  description  = "Git URL of the repository to clone into /home/dev on first start, for example https://github.com/plume-works/images.git. A private repository needs a GITHUB_TOKEN Coder secret."
  type         = "string"
  mutable      = false
  icon         = "/icon/git.svg"
}

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  dir  = local.repo_dir

  # In the agent's environment, so in its startup script, every terminal and app, and (through the import below)
  # every agent service.
  env = {
    REPO_URL            = data.coder_parameter.repo_url.value
    REPO_DIR            = local.repo_dir
    GIT_AUTHOR_NAME     = local.git_name
    GIT_AUTHOR_EMAIL    = local.git_email
    GIT_COMMITTER_NAME  = local.git_name
    GIT_COMMITTER_EMAIL = local.git_email
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
    if [ ! -d "$REPO_DIR/.git" ] && ! git clone "$REPO_URL" "$REPO_DIR"; then
      cloned=false
      echo "ERROR: could not clone $REPO_URL into $REPO_DIR (see git's message above)." >&2
      echo "ERROR: starting the agent services anyway; clone the repository from a terminal." >&2
    fi
    systemctl --user import-environment $(compgen -e)
    systemctl --user start agent-services.target
    [ "$cloned" = true ]
  EOT

  # VS Code Desktop is the agent's built-in button.
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
  install_version = "4.145.2"
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

# The Coder template image, by tag and digest. Pulled once per digest. Kept on the host when a workspace is deleted,
# because other workspaces use it too.
resource "docker_image" "main" {
  # Renovate proposes digest bumps: its terraform manager reads a docker_image name only as a literal string, so
  # keep the reference here, not in a local or variable.
  name         = "ghcr.io/plume-works/coder-template:edge@sha256:de20df61e2c035587c3a021ee1a7b4ae5d791e81a44219ca547555495a3e59ae"
  keep_locally = true
}

# The only state that persists: home, and the inner Docker engine's storage (containerd's included), each in a
# volume mounted at the path below. Never replaced or deleted by a template change; deleted with the workspace.
locals {
  state_volumes = {
    home       = "/home/dev"
    docker     = "/var/lib/docker"
    containerd = "/var/lib/containerd"
  }
}

resource "docker_volume" "state" {
  for_each = local.state_volumes
  name     = "coder-${data.coder_workspace.me.id}-${each.key}"
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

# The volumes had one resource each before: without these, Terraform would replace them, home included, in every
# workspace made from an earlier version of this template.
moved {
  from = docker_volume.home
  to   = docker_volume.state["home"]
}
moved {
  from = docker_volume.docker
  to   = docker_volume.state["docker"]
}
moved {
  from = docker_volume.containerd
  to   = docker_volume.state["containerd"]
}

# Recreated at every start, so everything outside the three volumes comes fresh from the image.
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
  # A Coder access URL on localhost means the host, as in Coder's own Docker template.
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

  dynamic "volumes" {
    for_each = local.state_volumes
    content {
      container_path = volumes.value
      volume_name    = docker_volume.state[volumes.key].name
      read_only      = false
    }
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
