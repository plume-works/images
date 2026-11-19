import pytest

from conftest import run_container

pytestmark = pytest.mark.privileged


def test_engine_answers(engine):
    result = engine.sh("docker info")
    assert result.returncode == 0, result.stderr


def test_second_call_keeps_the_same_daemon(engine):
    before = engine.sh("cat /run/docker.pid").stdout
    for user in ["root", "dev"]:
        result = engine.sh("start-docker", user=user)
        assert result.returncode == 0, f"{user}: {result.stderr}"
    after = engine.sh("cat /run/docker.pid").stdout
    assert before.strip() and before == after, f"pid file changed: {before!r} -> {after!r}"


def test_dev_uses_the_engine_without_sudo(engine, inner_image):
    result = engine.sh(f"docker run --rm {inner_image}", user="dev")
    assert "Hello from Docker!" in result.stdout, result.stdout + result.stderr


def test_container_with_a_memory_limit_runs(engine, inner_image):
    result = engine.sh(f"docker run --rm --memory 64m {inner_image}")
    assert result.returncode == 0, result.stdout + result.stderr


def test_docker_storage_is_a_mount(engine):
    result = engine.sh("findmnt /var/lib/docker")
    assert result.returncode == 0, result.stdout + result.stderr


def test_log_is_appended(engine):
    engine.sh("echo marker-line >> /var/log/dockerd.log")
    started = engine.sh("start-docker")
    assert started.returncode == 0, f"start-docker exit {started.returncode}: {started.stdout}{started.stderr}"
    log = engine.sh("cat /var/log/dockerd.log").stdout
    assert "marker-line" in log, f"marker missing from log, which holds: {log[:500]!r}"


def test_refuses_overlay_storage(image):
    with run_container(image, "--privileged") as c:
        result = c.sh("umount /var/lib/docker && start-docker")
        assert result.returncode != 0, result.stdout + result.stderr
        assert "mount a volume at /var/lib/docker" in result.stderr, result.stderr


def test_timeout_stops_the_daemon_it_started(image):
    # A real dockerd can answer within the first check, so a shim `docker` that always
    # fails stands in for "never became ready". --init: the killed daemon's containerd is
    # orphaned and needs a PID 1 that reaps it, or the next dockerd waits on its zombie.
    with run_container(image, "--privileged", "--init") as c:
        c.sh("mkdir /tmp/shim && printf '#!/bin/sh\\nexit 1\\n' >/tmp/shim/docker && chmod +x /tmp/shim/docker")
        result = c.sh("PATH=/tmp/shim:$PATH START_DOCKER_TIMEOUT=1 start-docker")
        assert result.returncode == 1, f"exit {result.returncode}: {result.stdout}{result.stderr}"
        log = c.sh("cat /var/log/dockerd.log").stdout
        assert log.strip(), "start-docker never launched dockerd: /var/log/dockerd.log is empty"
        left = c.sh("pgrep -x dockerd")
        assert left.stdout.strip() == "", f"dockerd left behind: {left.stdout!r}"
        again = c.sh("start-docker")
        assert again.returncode == 0, again.stdout + again.stderr


def test_concurrent_first_calls_start_one_daemon(image):
    with run_container(image, "--privileged") as c:
        result = c.sh("start-docker & a=$!; start-docker & b=$!; wait $a && wait $b")
        assert result.returncode == 0, f"a call failed, exit {result.returncode}: {result.stdout}{result.stderr}"
        count = c.sh("pgrep -xc dockerd")
        assert count.stdout.strip() == "1", f"dockerd count: {count.stdout!r}"
