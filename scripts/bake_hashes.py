"""Bake the sha256 of each tool's Linux release archives into the Core image Dockerfile.

Run from the repo root: uv run scripts/bake_hashes.py
Exits 1 with one line on stderr, leaving the Dockerfile untouched, if anything is off.
"""

import json
import os
import re
import sys
import urllib.error
import urllib.request
from collections.abc import Callable
from pathlib import Path

DOCKERFILE = Path("images/core/Dockerfile")

# name, repo, tag prefix, amd64 asset, arm64 asset
TOOLS = [
    ("UV", "astral-sh/uv", "", "uv-x86_64-unknown-linux-gnu.tar.gz", "uv-aarch64-unknown-linux-gnu.tar.gz"),
    ("OPENCODE", "anomalyco/opencode", "v", "opencode-linux-x64.tar.gz", "opencode-linux-arm64.tar.gz"),
]


class Refused(Exception):
    pass


def fetch_release(repo: str, tag: str) -> dict:
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repo}/releases/tags/{tag}",
        headers={"Accept": "application/vnd.github+json"},
    )
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except ValueError as error:
        raise Refused(f"GitHub sent a non-JSON answer for {repo} {tag}") from error
    except urllib.error.HTTPError as error:
        raise Refused(f"GitHub answered {error.code} for {repo} {tag}") from error
    except urllib.error.URLError as error:
        raise Refused(f"could not reach GitHub for {repo} {tag}: {error.reason}") from error


def _arg(name: str) -> re.Pattern:
    return re.compile(rf"^ARG {name}=.*$", re.MULTILINE)


def _digest(release: dict, repo: str, tag: str, asset: str) -> str:
    found = next((a for a in release.get("assets", []) if a.get("name") == asset), None)
    if found is None:
        raise Refused(f"{repo} {tag} has no asset {asset}")
    digest = found.get("digest")
    if not digest:
        raise Refused(f"{repo} {tag} asset {asset} has no digest")
    algorithm, _, value = digest.partition(":")
    if algorithm != "sha256" or not re.fullmatch(r"[0-9a-f]{64}", value):
        raise Refused(f"{repo} {tag} asset {asset} digest is not sha256: {digest}")
    return value


def bake(dockerfile: str, fetch: Callable[[str, str], dict] = fetch_release) -> str:
    for name, repo, prefix, amd64, arm64 in TOOLS:
        version_arg = _arg(f"{name}_VERSION")
        found = version_arg.search(dockerfile)
        if not found:
            raise Refused(f"Dockerfile has no ARG {name}_VERSION")
        version = found.group(0).split("=", 1)[1].strip()
        tag = prefix + version
        release = fetch(repo, tag)
        if release.get("immutable") is not True:
            raise Refused(f"{repo} {tag} is not an immutable release")
        for arch, asset in (("AMD64", amd64), ("ARM64", arm64)):
            arg = f"{name}_SHA256_{arch}"
            pattern = _arg(arg)
            if not pattern.search(dockerfile):
                raise Refused(f"Dockerfile has no ARG {arg}")
            line = f"ARG {arg}={_digest(release, repo, tag, asset)}"
            dockerfile = pattern.sub(lambda _: line, dockerfile)
    return dockerfile


def main() -> int:
    try:
        original = DOCKERFILE.read_bytes().decode()
        updated = bake(original)
    except (Refused, OSError) as error:
        print(f"bake_hashes: {error}", file=sys.stderr)
        return 1
    DOCKERFILE.write_bytes(updated.encode())
    return 0


if __name__ == "__main__":
    sys.exit(main())
