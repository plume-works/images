import json
import re
import shlex
import subprocess

import pytest

USERS = ["root", "dev"]

# Binary name -> the command that makes it print its version.
TOOLS = {
    "git": "git --version",
    "git-lfs": "git lfs version",
    "gh": "gh --version",
    "uv": "uv --version",
    "uvx": "uvx --version",
    "python3": "python3 --version",
    "bun": "bun --version",
    "bunx": "bunx --version",
    "claude": "claude --version",
    "opencode": "opencode --version",
    "gcc": "gcc --version",
    "make": "make --version",
    "cmake": "cmake --version",
    "ninja": "ninja --version",
    "fish": "fish --version",
    "curl": "curl --version",
    "jq": "jq --version",
    "rg": "rg --version",
    "less": "less --version",
    "docker": "docker --version",
}


def inspect(image: str, fmt: str) -> str:
    out = subprocess.run(
        ["docker", "image", "inspect", "--format", fmt, image],
        capture_output=True,
        text=True,
    )
    assert out.returncode == 0, f"docker image inspect failed: {out.stderr}"
    return out.stdout.strip()


def test_no_entrypoint(image):
    entrypoint = json.loads(inspect(image, "{{json .Config.Entrypoint}}"))
    assert entrypoint is None, f"Entrypoint is {entrypoint!r}"


def test_source_label(image):
    source = inspect(image, '{{index .Config.Labels "org.opencontainers.image.source"}}')
    assert source == "https://github.com/plume-works/images", f"source label is {source!r}"


def test_no_empty_version_label(image):
    # The base image's own version label (26.04) is inherited and fine; ours was empty.
    labels = json.loads(inspect(image, "{{json .Config.Labels}}")) or {}
    version = labels.get("org.opencontainers.image.version")
    assert version != "", f"version label is {version!r}"


def test_dev_is_uid_and_gid_1000(plain):
    ids = plain.sh("id -un; id -u; id -g", user="dev").stdout.split()
    assert ids == ["dev", "1000", "1000"], f"dev's name, uid, gid are {ids!r}"


def test_dev_has_passwordless_sudo(plain):
    uid = plain.sh("sudo -n id -u", user="dev").stdout.strip()
    assert uid == "0", f"sudo -n id -u printed {uid!r}"


def test_dev_home_is_owned_by_dev(plain):
    stray = plain.sh("find /home/dev ! -user dev -o ! -group dev").stdout.strip()
    assert stray == "", f"not owned by dev: {stray!r}"


def test_engine_is_not_running_by_default(plain):
    result = plain.sh("docker info", user="dev")
    assert result.returncode != 0, "docker info succeeded without start-dockerd"
    pgrep = plain.sh("pgrep -x dockerd")
    assert pgrep.returncode != 0, f"dockerd is running: pgrep printed {pgrep.stdout!r}"


def test_docker_data_is_on_a_volume(plain):
    result = plain.sh("grep ' /var/lib/docker ' /proc/mounts")
    assert result.returncode == 0, f"/var/lib/docker is not a mount; mounts: {plain.sh('cat /proc/mounts').stdout!r}, grep printed {result.stdout!r}"


def test_default_user_is_root(image):
    out = subprocess.run(["docker", "run", "--rm", image, "id", "-u"], capture_output=True, text=True)
    assert out.stdout.strip() == "0", f"id -u printed {out.stdout!r}, stderr {out.stderr!r}"


def test_dev_shell_is_bash(plain):
    entry = plain.sh("getent passwd dev").stdout.strip()
    assert entry.split(":")[-1:] == ["/bin/bash"], f"getent passwd dev: {entry!r}"


def test_no_ubuntu_user(plain):
    passwd = plain.sh("getent passwd ubuntu")
    assert passwd.returncode != 0, f"getent passwd ubuntu: {passwd.stdout!r}"
    subuid = plain.sh("cat /etc/subuid").stdout
    assert "ubuntu" not in subuid, f"/etc/subuid: {subuid!r}"


def test_dev_is_in_the_docker_group(plain):
    groups = plain.sh("id -nG", user="dev").stdout.split()
    assert "docker" in groups, f"dev's groups are {groups!r}"


@pytest.mark.parametrize("user", USERS)
@pytest.mark.parametrize("tool", TOOLS)
def test_tool_answers_from_a_system_path(plain, tool, user):
    path = plain.sh(f'readlink -f "$(command -v {tool})"', user=user).stdout.strip()
    assert path and not path.startswith(("/root/", "/home/")), f"{tool} resolves to {path!r}"
    result = plain.sh(TOOLS[tool], user=user)
    assert result.returncode == 0 and result.stdout.strip(), (
        f"`{TOOLS[tool]}` as {user} exited {result.returncode}: {result.stdout!r} {result.stderr!r}"
    )


def test_buildx_and_compose_answer(plain):
    for cmd in ("docker buildx version", "docker compose version"):
        result = plain.sh(cmd, user="dev")
        assert result.returncode == 0, f"`{cmd}` exited {result.returncode}: {result.stderr}"


def test_python3_is_the_system_python(plain):
    path = plain.sh('readlink -f "$(command -v python3)"').stdout.strip()
    assert path.startswith("/usr/bin/"), f"python3 resolves to {path!r}"


@pytest.mark.parametrize("tool", ["python", "node", "nodejs", "npm", "npx"])
def test_tool_is_absent(plain, tool):
    found = plain.sh(f"command -v {tool}")
    assert found.returncode != 0, f"{tool} found at {found.stdout!r}"


def test_opencode_is_version_2(plain):
    version = plain.sh("opencode --version", user="dev").stdout
    assert re.search(r"(?<!\d)2\.\d+\.\d+", version), f"opencode --version printed {version!r}"


def test_homes_hold_only_shell_startup_files(image):
    out = subprocess.run(
        ["docker", "run", "--rm", image, "find", "/root", "/home/dev", "-mindepth", "1", "-maxdepth", "1"],
        capture_output=True,
        text=True,
    )
    found = {path.rsplit("/", 1)[1] for path in out.stdout.split()}
    assert found <= {".bashrc", ".profile", ".bash_logout"}, f"homes hold {sorted(found)!r}"


FILL = "printf 'protocol=https\\nhost={host}\\n\\n' | GIT_TERMINAL_PROMPT=0 timeout 20 git credential fill"


@pytest.mark.parametrize("user", USERS)
@pytest.mark.parametrize("var", ["GH_TOKEN", "GITHUB_TOKEN"])
def test_git_gets_a_credential_through_gh(plain, user, var):
    result = plain.sh(FILL.format(host="github.com"), user=user, env={var: "t-" + var})
    assert f"password=t-{var}" in result.stdout.splitlines(), f"stdout {result.stdout!r}, stderr {result.stderr!r}"


@pytest.mark.parametrize("user", USERS)
def test_git_fails_without_a_token_and_does_not_prompt(plain, user):
    result = plain.sh(FILL.format(host="github.com"), user=user, timeout=40)
    assert result.returncode != 0, f"git filled a credential without a token: {result.stdout!r}"


def test_gist_host_uses_gh_too(plain):
    result = plain.sh(FILL.format(host="gist.github.com"), env={"GH_TOKEN": "t-gist"})
    assert "password=t-gist" in result.stdout.splitlines(), f"stdout {result.stdout!r}, stderr {result.stderr!r}"


def says(plain, script, expected, user="root"):
    result = plain.sh(script, user=user, timeout=90)
    out = result.stdout + result.stderr
    assert re.search(expected, out, re.M), f"`{script}` as {user} printed {out!r}"


@pytest.mark.parametrize("user", USERS)
@pytest.mark.parametrize(
    "script, expected",
    [
        ("claude mcp list", "^No MCP servers configured"),
        ("claude plugin list", "^No plugins installed"),
        ("claude auth status", '"loggedIn": false'),
    ],
)
def test_claude_is_bare(plain, user, script, expected):
    says(plain, script, expected, user)


# --standalone runs a private server for the command instead of leaving a per-user background service.
@pytest.mark.parametrize("user", USERS)
@pytest.mark.parametrize(
    "args, expected",
    [
        ("mcp list", "^No MCP servers configured"),
        ("plugin list", "^No plugins found"),
        ("auth list", "No authenticated integrations"),
    ],
)
def test_opencode_is_bare(plain, user, args, expected):
    says(plain, f"timeout 60 opencode --standalone {args}", expected, user)


def as_how(how: str, command: str) -> tuple[str, str]:
    """(user, script) to run the command as root, as dev, or in a fresh login of dev (which drops the environment)."""
    if how == "login":
        return "root", f"su -l dev -c {shlex.quote(command)}"
    return how, command


@pytest.mark.parametrize("how", ["root", "dev", "login"])
def test_claude_refuses_to_update(plain, how):
    user, script = as_how(how, "timeout 60 claude update")
    says(plain, script, "Updates are disabled", user)


# OpenCode checks for updates when its terminal UI starts: run it a few seconds in a pseudo-terminal.
OPENCODE_UI = 'cd /tmp && timeout 8 script -qec "opencode --standalone --print-logs 2>&1" /dev/null </dev/null'


@pytest.mark.parametrize("how", ["root", "dev", "login"])
def test_opencode_skips_its_update_check(plain, how):
    user, script = as_how(how, OPENCODE_UI)
    says(plain, script, 'message="update check skipped" reason=disabled', user)


def test_claude_refuses_to_update_with_an_empty_environment(plain):
    says(plain, "env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=/root claude update", "Updates are disabled")
