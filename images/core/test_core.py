import json
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
    assert plain.sh("pgrep -x dockerd").returncode != 0, "dockerd is running"


def test_docker_data_is_on_a_volume(plain):
    result = plain.sh("grep -q ' /var/lib/docker ' /proc/mounts")
    assert result.returncode == 0, "/var/lib/docker is not a mount"
