import io
import urllib.error

import pytest

import bake_hashes
from bake_hashes import Refused, bake

DOCKERFILE = """FROM ubuntu
ARG UV_VERSION=0.13.9
ARG UV_SHA256_AMD64=old
ARG UV_SHA256_ARM64=old
RUN echo hi
ARG OPENCODE_VERSION=2.3.2
ARG OPENCODE_SHA256_AMD64=old
ARG OPENCODE_SHA256_ARM64=old
"""

ASSETS = {
    "astral-sh/uv": ("uv-x86_64-unknown-linux-gnu.tar.gz", "uv-aarch64-unknown-linux-gnu.tar.gz"),
    "anomalyco/opencode": ("opencode-linux-x64.tar.gz", "opencode-linux-arm64.tar.gz"),
}
HEX = {
    "astral-sh/uv": ("a" * 64, "b" * 64),
    "anomalyco/opencode": ("c" * 64, "d" * 64),
}


def release(repo, **overrides):
    names, digests = ASSETS[repo], HEX[repo]
    rel = {
        "immutable": True,
        "assets": [{"name": n, "digest": f"sha256:{d}"} for n, d in zip(names, digests)],
    }
    rel.update(overrides)
    return rel


def fake_fetch(**overrides_by_repo):
    calls = []

    def fetch(repo, tag):
        calls.append((repo, tag))
        return release(repo, **overrides_by_repo.get(repo, {}))

    fetch.calls = calls
    return fetch


def test_writes_both_hashes_for_each_tool():
    result = bake(DOCKERFILE, fake_fetch())
    assert f"ARG UV_SHA256_AMD64={'a' * 64}\n" in result
    assert f"ARG UV_SHA256_ARM64={'b' * 64}\n" in result
    assert f"ARG OPENCODE_SHA256_AMD64={'c' * 64}\n" in result
    assert f"ARG OPENCODE_SHA256_ARM64={'d' * 64}\n" in result


def test_asks_for_the_right_tags():
    fetch = fake_fetch()
    bake(DOCKERFILE, fetch)
    assert fetch.calls == [("astral-sh/uv", "0.13.9"), ("anomalyco/opencode", "v2.3.2")]


def test_leaves_other_lines_alone():
    result = bake(DOCKERFILE, fake_fetch())
    assert len(result.splitlines()) == len(DOCKERFILE.splitlines())
    for old, new in zip(DOCKERFILE.splitlines(), result.splitlines()):
        if "_SHA256_" not in old:
            assert old == new


def test_refuses_a_mutable_release():
    with pytest.raises(Refused, match="immutable"):
        bake(DOCKERFILE, fake_fetch(**{"astral-sh/uv": {"immutable": False}}))


def test_refuses_when_immutable_is_missing():
    def fetch(repo, tag):
        rel = release(repo)
        del rel["immutable"]
        return rel

    with pytest.raises(Refused, match="immutable"):
        bake(DOCKERFILE, fetch)


def test_refuses_a_missing_asset():
    with pytest.raises(Refused, match="uv-aarch64-unknown-linux-gnu.tar.gz"):
        bake(DOCKERFILE, fake_fetch(**{"astral-sh/uv": {"assets": release("astral-sh/uv")["assets"][:1]}}))


def test_refuses_an_asset_without_a_digest():
    assets = [{"name": n, "digest": None} for n in ASSETS["anomalyco/opencode"]]
    with pytest.raises(Refused, match="digest"):
        bake(DOCKERFILE, fake_fetch(**{"anomalyco/opencode": {"assets": assets}}))


def test_refuses_a_digest_that_is_not_sha256():
    assets = [{"name": n, "digest": "sha512:" + "e" * 128} for n in ASSETS["astral-sh/uv"]]
    with pytest.raises(Refused, match="sha256"):
        bake(DOCKERFILE, fake_fetch(**{"astral-sh/uv": {"assets": assets}}))


@pytest.mark.parametrize("name", ["UV_SHA256_ARM64", "UV_VERSION"])
def test_refuses_a_dockerfile_without_the_arg(name):
    text = "".join(l for l in DOCKERFILE.splitlines(True) if not l.startswith(f"ARG {name}="))
    with pytest.raises(Refused, match=name):
        bake(text, fake_fetch())


def test_main_leaves_the_file_untouched_on_refusal(tmp_path, monkeypatch, capsys):
    path = tmp_path / "images/core/Dockerfile"
    path.parent.mkdir(parents=True)
    path.write_bytes(DOCKERFILE.encode())
    monkeypatch.chdir(tmp_path)
    fetch = fake_fetch(**{"anomalyco/opencode": {"immutable": False}})
    monkeypatch.setattr(bake_hashes, "bake", lambda text: bake(text, fetch))
    assert bake_hashes.main() == 1
    assert path.read_bytes() == DOCKERFILE.encode()
    assert len(capsys.readouterr().err.splitlines()) == 1


def test_http_error_is_refused(monkeypatch):
    def urlopen(request, *args, **kwargs):
        raise urllib.error.HTTPError(request.full_url, 403, "rate limited", {}, io.BytesIO())

    monkeypatch.setattr(bake_hashes.urllib.request, "urlopen", urlopen)
    with pytest.raises(Refused, match="403"):
        bake(DOCKERFILE)


class FakeResponse(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


@pytest.mark.parametrize(
    "env, expected",
    [({"GITHUB_TOKEN": "t0k"}, "Bearer t0k"), ({"GH_TOKEN": "g1t"}, "Bearer g1t"), ({}, None)],
)
def test_fetch_release_authorization(monkeypatch, env, expected):
    monkeypatch.delenv("GITHUB_TOKEN", raising=False)
    monkeypatch.delenv("GH_TOKEN", raising=False)
    for key, value in env.items():
        monkeypatch.setenv(key, value)
    seen = []

    def urlopen(request, *args, **kwargs):
        seen.append(request.get_header("Authorization"))
        return FakeResponse(b"{}")

    monkeypatch.setattr(bake_hashes.urllib.request, "urlopen", urlopen)
    bake_hashes.fetch_release("astral-sh/uv", "0.13.9")
    assert seen == [expected]


def test_non_json_body_is_refused(monkeypatch):
    monkeypatch.setattr(
        bake_hashes.urllib.request, "urlopen", lambda *a, **k: FakeResponse(b"<html>")
    )
    with pytest.raises(Refused, match="non-JSON"):
        bake_hashes.fetch_release("astral-sh/uv", "0.13.9")
