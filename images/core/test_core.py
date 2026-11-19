import json
import re
import subprocess

import pytest

TOOLS = {
    "git": "git --version",
    "git-lfs": "git lfs version",
    "gh": "gh --version",
    "uv": "uv --version",
    "uvx": "uvx --version",
    "bun": "bun --version",
    "bunx": "bunx --version",
    "claude": "claude --version",
    "opencode": "opencode --version",
    "gcc": "gcc --version",
    "make": "make --version",
    "curl": "curl --version",
    "jq": "jq --version",
    "rg": "rg --version",
    "less": "less --version",
    "docker": "docker --version",
    "buildx": "docker buildx version",
    "compose": "docker compose version",
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


@pytest.mark.parametrize("tool", TOOLS)
def test_tool_runs(plain, tool):
    result = plain.sh(TOOLS[tool], user="dev")
    assert result.returncode == 0, f"`{TOOLS[tool]}` exited {result.returncode}: {result.stderr}"


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


SYSTEM_TOOLS = [
    "git", "gh", "git-lfs", "uv", "uvx", "python3", "bun", "bunx", "cmake",
    "ninja", "fish", "jq", "rg", "claude", "opencode", "docker",
]


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


@pytest.mark.parametrize("user", ["root", "dev"])
@pytest.mark.parametrize("tool", SYSTEM_TOOLS)
def test_tool_answers_from_a_system_path(plain, tool, user):
    path = plain.sh(f'readlink -f "$(command -v {tool})"', user=user).stdout.strip()
    assert path and not path.startswith(("/root/", "/home/")), f"{tool} resolves to {path!r}"
    result = plain.sh(f"{tool} --version", user=user)
    assert result.returncode == 0 and result.stdout.strip(), (
        f"`{tool} --version` as {user} exited {result.returncode}: {result.stdout!r} {result.stderr!r}"
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
