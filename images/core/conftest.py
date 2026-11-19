import subprocess
from contextlib import contextmanager
from typing import Iterator

import pytest


class Container:
    def __init__(self, name: str):
        self.name = name

    def sh(
        self,
        script: str,
        user: str = "root",
        env: dict[str, str] | None = None,
        timeout: int = 120,
    ) -> subprocess.CompletedProcess[str]:
        cmd = ["docker", "exec", "-u", user]
        for key, value in (env or {}).items():
            cmd += ["-e", f"{key}={value}"]
        cmd += [self.name, "bash", "-c", script]
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


@contextmanager
def run_container(image: str, *docker_args: str) -> Iterator[Container]:
    started = subprocess.run(
        ["docker", "run", "-d", "--rm", *docker_args, image, "sleep", "infinity"],
        capture_output=True,
        text=True,
    )
    assert started.returncode == 0, f"docker run failed: {started.stderr}"
    name = started.stdout.strip()
    try:
        yield Container(name)
    finally:
        subprocess.run(["docker", "rm", "-f", "-v", name], capture_output=True)


@pytest.fixture(scope="session")
def image(request) -> str:
    return request.config.getoption("--image")


@pytest.fixture(scope="session")
def inner_image(request) -> str:
    return request.config.getoption("--inner-image")


@pytest.fixture(scope="session")
def plain(image) -> Iterator[Container]:
    with run_container(image) as container:
        yield container
