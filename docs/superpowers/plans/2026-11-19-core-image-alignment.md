# Core Image Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the core image on `core-images-try2` in line with issue 4, fix the handoff defects, replace the shell test with a pytest suite, and move version upkeep to self-hosted Renovate with hashes baked into the Dockerfile.

**Architecture:** This branch's Dockerfile is patched, not replaced. `uv` and OpenCode become GitHub release archives checked against sha256 values held in `ARG`s; one Python script fills those `ARG`s from GitHub's release API and is both the build-time helper and Renovate's post-upgrade command. Tests drive containers from the host with pytest; CI builds and tests per architecture, then publishes `pr-N` or `edge` only if the pushed image's config digest equals the tested one.

**Tech Stack:** Docker Buildx bake, Ubuntu 26.04, pytest through `uv`, GitHub Actions, Renovate (run with `bunx` on the runner).

**Spec:** `docs/superpowers/specs/2026-11-19-core-image-alignment-design.md`. Read it first. Where it is silent, issue 4 decides (`curl -s https://api.github.com/repos/plume-works/images/issues/4`).

## Global Constraints

- YAGNI, KISS, DRY (AGENTS.md). No file, option or abstraction the spec does not ask for.
- Scope is the core image and repo setup. No other image.
- Read `GLOSSARY.md` (once Task 8 creates it) and `docs/adr/` before working in an area. Use the term **Core image**.
- Nothing is installed under `/root` or `/home`. No Node.js. No `uv`-managed Python. No bare `python`, no `WORKDIR`, no `USER` line, no `unzip` or `xz-utils`.
- A download's checksum is never fetched at build time. The Dockerfile compares against a baked `ARG`.
- Versions to bake: the newest release of each tool that is at least 3 days old on the day of the build (10 days for an `x.y.0`).
- Every GitHub Action is pinned by commit SHA with the tag in a trailing comment. Resolve a SHA with `git ls-remote https://github.com/<owner>/<repo> 'refs/tags/<tag>^{}' 'refs/tags/<tag>'`. Checkout uses `persist-credentials: false`. Workflows default to `permissions: contents: read`.
- Runners: `ubuntu-26.04` and `ubuntu-26.04-arm`.
- Check names `build (amd64)` and `build (arm64)` must not change; branch protection will require them.
- PR 18 is reference material at the local ref `pr-18` (`git fetch origin pull/18/head:pr-18` if it is missing). Copy only what a task names.
- Commit messages and PR text carry no attribution lines.
- Do not push before Task 9. Intermediate commits leave CI inconsistent.
- If Claude Code installed with Bun cannot pass the tests in Task 4, stop and ask Anton. Do not add Node.js or switch to the native binary.
- **Dismissed findings:** whenever a reviewer's finding is closed without a fix, record it (finding, who dismissed it, why). Task 9 reports every one. Two are carried in from earlier reviews and stay dismissed: `docker info` calls in the starter script are not time-bounded; a non-numeric timeout gives no hint.

## Review Focus

Failure modes the spec implies; each has a test or check in the task named.

1. Two `start-docker` calls at the same moment in a fresh container: exactly one `dockerd` must result. (Task 5)
2. A release that is not immutable, or lacks an archive, or has no recorded digest: the hash script must exit non-zero and leave the Dockerfile byte-for-byte unchanged. (Task 2)
3. The Dockerfile no longer has an `ARG` the hash script expects (someone renamed it): the script must fail, not silently write nothing. (Task 2)
4. GitHub's API answers with an error or a rate limit: the script must fail with the status in its message and change nothing. (Task 2)
5. An archive whose bytes do not match the baked hash: the image build must fail. (Task 3)

## File Structure

| Path | Responsibility |
|---|---|
| `images/core/Dockerfile` | The core image (moved from `core/`) |
| `images/core/start-docker` | Starts the engine on demand (replaces `core/start-dockerd`) |
| `images/core/.dockerignore` | Admits only `start-docker` to the build context |
| `images/core/conftest.py` | Container fixtures for the core tests |
| `images/core/test_core.py` | Checks that need no privilege |
| `images/core/test_engine.py` | Checks marked `privileged` |
| `conftest.py` | The pytest options `--image` and `--inner-image` |
| `pyproject.toml`, `uv.lock` | Pin pytest; pytest settings |
| `scripts/bake_hashes.py` | Writes release hashes into the Dockerfile |
| `scripts/test_bake_hashes.py` | Unit tests for it, GitHub faked |
| `docker-bake.hcl` | Build definition |
| `.github/workflows/build.yml`, `pr-cleanup.yml`, `lint.yml`, `renovate.yml` | Pipeline |
| `renovate.json` | Renovate config (root; `.github/renovate.json` is removed) |
| `.hadolint.yaml` | hadolint ignores |

`test_engine.py` is split from `test_core.py` so the whole file carries the `privileged` marker.

---

### Task 1: Layout, `uv` on the host, pytest harness

Moves the image to `images/core/` and replaces `core/test.sh` with a pytest harness holding the checks that already pass on today's image.

**Files:**
- Move: `core/` → `images/core/` (`git mv`); `images/core/start-dockerd` → `images/core/start-docker`
- Delete: `images/core/test.sh` (after its checks are ported)
- Create: `pyproject.toml`, `uv.lock`, `conftest.py`, `images/core/conftest.py`, `images/core/test_core.py`
- Modify: `docker-bake.hcl`, `images/core/Dockerfile` (the `COPY` line only), `images/core/.dockerignore`, `.devcontainer.json`, `.gitignore`

**Interfaces:**
- Produces, in `conftest.py` (root): options `--image` (default `ghcr.io/plume-works/core:edge`) and `--inner-image` (default `ghcr.io/plume-works/hello-world@sha256:1e4c05b897a751332ce85c7e9449da2d93514ea2dea6dbb0e2753c9e949b2bfa`).
- Produces, in `images/core/conftest.py`:
  - `class Container` with `name: str` and `sh(script: str, user: str = "root", env: dict[str, str] | None = None, timeout: int = 120) -> subprocess.CompletedProcess[str]`. It runs `docker exec [-u user] [-e K=V ...] <name> bash -c <script>`, captures text output, and never raises on a non-zero exit.
  - `run_container(image: str, *docker_args: str) -> Iterator[Container]`, a context manager: `docker run -d --rm <docker_args> <image> sleep infinity`, and `docker rm -f -v` on exit.
  - Session fixtures `image -> str`, `inner_image -> str`, `plain -> Container` (no extra flags).
- Produces: marker `privileged`, registered in `pyproject.toml` with `--strict-markers`.

- [ ] **Step 1: Merge `main`**

```sh
git fetch origin main && git merge origin/main
```

Expected: a merge commit that adds only a root `renovate.json`. Task 7 replaces that file.

- [ ] **Step 2: Put `uv` on this host and in the dev container**

Neither `uv` nor `python3` exists on the host today. Add to `.devcontainer.json`:

```json
"postCreateCommand": "sh -c 'curl -LsSf https://astral.sh/uv/$(sed -n s/^ARG.UV_VERSION=//p images/core/Dockerfile)/install.sh | sh'"
```

The dev container, CI and the image all take the `uv` version from the one `ARG UV_VERSION` line that Task 3 adds. Until then run the same install by hand with version `0.13.9`. Verify: `uv --version` prints a version.

- [ ] **Step 3: Move the directory and fix references**

`git mv core images/core`, rename the script, change the Dockerfile's `COPY` to `start-docker` (the script's content changes in Task 5), and in `docker-bake.hcl` set `context = "images/core"` and delete the `org.opencontainers.image.version` label. Replace `images/core/.dockerignore` with:

```
*
!start-docker
```

Add `transcripts/`, `.venv/`, `__pycache__/` and `.pytest_cache/` to `.gitignore`.

Verify: `docker buildx bake core` succeeds and `docker buildx bake core --print` shows no `image.version` label.

- [ ] **Step 4: Write `pyproject.toml` and lock it**

Project name `images`, `[tool.uv] package = false`, a `dev` dependency group holding `pytest==<newest release at least 3 days old>`, and:

```toml
[tool.pytest.ini_options]
testpaths = ["images", "scripts"]
addopts = "--strict-markers"
markers = ["privileged: needs a host that allows privileged containers"]
```

Run `uv lock`. Commit `uv.lock`.

- [ ] **Step 5: Write the harness and the first tests**

Write both `conftest.py` files to the Interfaces above. In `images/core/test_core.py`, port every check of `images/core/test.sh` that still describes the target image, as separate tests. At minimum:

```python
def test_no_entrypoint(image): ...        # docker image inspect: Entrypoint is null
def test_source_label(image): ...         # org.opencontainers.image.source == "https://github.com/plume-works/images"
def test_no_version_label(image): ...     # org.opencontainers.image.version absent
def test_dev_is_uid_and_gid_1000(plain): ...
def test_dev_has_passwordless_sudo(plain): ...   # plain.sh("sudo -n id -u", user="dev") prints 0
def test_engine_is_not_running_by_default(plain): ...   # docker info fails
```

Every assertion message states what was seen, for example `assert uid == "1000", f"dev's uid is {uid!r}"`.

- [ ] **Step 6: Run**

Run: `uv run pytest images/core -v`
Expected: all pass against the image built in Step 3.

- [ ] **Step 7: Delete `images/core/test.sh` and commit**

```sh
git rm images/core/test.sh
git add -A && git commit -m "Move core to images/core and test it with pytest"
```

---

### Task 2: The hash script

**Files:**
- Create: `scripts/bake_hashes.py`, `scripts/test_bake_hashes.py`

**Interfaces:**
- Produces: the command `uv run scripts/bake_hashes.py`, run from the repo root with no arguments. It rewrites `images/core/Dockerfile` in place and exits 0, or prints one line to stderr and exits 1 with the file untouched. Standard library only.
- Produces: the `ARG` contract Task 3 must follow. For each tool, three lines anywhere in the Dockerfile:

  ```
  ARG <NAME>_VERSION=<version>
  ARG <NAME>_SHA256_AMD64=<64 hex>
  ARG <NAME>_SHA256_ARM64=<64 hex>
  ```

- The tool table inside the script:

  | `NAME` | Repo | Release tag | AMD64 asset | ARM64 asset |
  |---|---|---|---|---|
  | `UV` | `astral-sh/uv` | `<version>` | `uv-x86_64-unknown-linux-gnu.tar.gz` | `uv-aarch64-unknown-linux-gnu.tar.gz` |
  | `OPENCODE` | `anomalyco/opencode` | `v<version>` | `opencode-linux-x64.tar.gz` | `opencode-linux-arm64.tar.gz` |

- Functions:
  - `class Refused(Exception)`
  - `fetch_release(repo: str, tag: str) -> dict`: `GET https://api.github.com/repos/<repo>/releases/tags/<tag>`, with `Authorization: Bearer` when `GITHUB_TOKEN` or `GH_TOKEN` is set. An HTTP error raises `Refused` naming the status code.
  - `bake(dockerfile: str, fetch: Callable[[str, str], dict] = fetch_release) -> str`: returns the new Dockerfile text, or raises `Refused`.
  - `main() -> int`

- [ ] **Step 1: Write the failing tests**

Each test builds a small Dockerfile string and a fake `fetch` returning a release dict shaped like GitHub's (`{"immutable": true, "assets": [{"name": ..., "digest": "sha256:<hex>"}]}`).

```python
def test_writes_both_hashes_for_each_tool(): ...
    # result contains "ARG UV_SHA256_AMD64=" + the faked amd64 hex, likewise ARM64 and OPENCODE
def test_asks_for_the_right_tags(): ...
    # fetch was called with ("astral-sh/uv", "0.13.9") and ("anomalyco/opencode", "v2.3.2")
def test_leaves_other_lines_alone(): ...
    # every line not starting "ARG <NAME>_SHA256_" is unchanged
def test_refuses_a_mutable_release(): ...          # "immutable": False -> Refused
def test_refuses_when_immutable_is_missing(): ...  # key absent -> Refused
def test_refuses_a_missing_asset(): ...            # Refused, message names the asset
def test_refuses_an_asset_without_a_digest(): ...  # "digest": None -> Refused
def test_refuses_a_digest_that_is_not_sha256(): ...  # "sha512:..." -> Refused
def test_refuses_a_dockerfile_without_the_hash_arg(): ...  # Refused, message names the ARG
def test_main_leaves_the_file_untouched_on_refusal(tmp_path, monkeypatch): ...
    # one tool succeeds and the other refuses: file bytes are unchanged, return value is 1
def test_http_error_is_refused(monkeypatch): ...
    # urlopen raises HTTPError 403 -> Refused, "403" in the message
```

- [ ] **Step 2: Run to see them fail**

Run: `uv run pytest scripts -v`
Expected: FAIL, `bake_hashes` cannot be imported.

- [ ] **Step 3: Implement `scripts/bake_hashes.py`**

`bake` works on all tools before returning, so `main` writes the file once or not at all.

- [ ] **Step 4: Run**

Run: `uv run pytest scripts -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```sh
git add scripts && git commit -m "Add the script that bakes release hashes into the Dockerfile"
```

---

### Task 3: The `dev` user and where each tool comes from

**Files:**
- Modify: `images/core/Dockerfile`, `images/core/test_core.py`

**Interfaces:**
- Consumes: `plain`, `Container.sh` (Task 1); the `ARG` contract and `uv run scripts/bake_hashes.py` (Task 2).
- Produces: the image's `ARG UV_VERSION` line, which Tasks 1, 6 and 7 read.

- [ ] **Step 1: Write the failing tests**

```python
TOOLS = ["git", "gh", "git-lfs", "uv", "uvx", "python3", "bun", "bunx", "cmake",
         "ninja", "fish", "jq", "rg", "claude", "opencode", "docker"]

def test_default_user_is_root(image): ...         # docker run --rm <image> id -u prints 0
def test_dev_shell_is_bash(plain): ...            # getent passwd dev, field 7 == "/bin/bash"
def test_no_ubuntu_user(plain): ...               # getent passwd ubuntu fails; /etc/subuid has no "ubuntu"
def test_dev_is_in_the_docker_group(plain): ...
@pytest.mark.parametrize("user", ["root", "dev"])
@pytest.mark.parametrize("tool", TOOLS)
def test_tool_answers_from_a_system_path(plain, tool, user): ...
    # readlink -f "$(command -v <tool>)" does not start with /root/ or /home/;
    # "<tool> --version" exits 0 with output
def test_buildx_and_compose_answer(plain): ...    # docker buildx version; docker compose version
def test_python3_is_the_system_python(plain): ... # readlink of command -v python3 is under /usr/bin
@pytest.mark.parametrize("tool", ["python", "node", "nodejs", "npm", "npx"])
def test_tool_is_absent(plain, tool): ...
def test_opencode_is_version_2(plain): ...        # opencode --version matches r"\b2\.\d+\.\d+"
```

- [ ] **Step 2: Run to see them fail**

Run: `uv run pytest images/core -v`
Expected: the new user, shell, `cmake`, `ninja` and OpenCode tests FAIL; Task 1's tests still pass.

- [ ] **Step 3: Change the Dockerfile**

- apt: add `cmake ninja-build python3` to the existing list. Remove nothing.
- User: replace the `groupmod`/`usermod` rename with `userdel --remove ubuntu`, then `useradd --create-home --uid 1000 --user-group --shell /bin/bash dev`, keep the sudoers file, and add `dev` to `docker` after Docker is installed. Delete the `USER dev` and `WORKDIR` lines.
- gh and Docker: unchanged (vendor apt repos, keys fetched at build).
- Bun: unchanged (`COPY --from=oven/bun` by digest).
- `uv`: delete the `COPY --from=ghcr.io/astral-sh/uv` line. Add the three `ARG`s under `# renovate: datasource=github-releases depName=astral-sh/uv`, and a `RUN` that picks the asset and the hash by `TARGETARCH`, downloads `https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/<asset>`, runs `sha256sum -c` against the baked value, and installs `uv` and `uvx` into `/usr/local/bin`. An unknown `TARGETARCH` fails the build.
- OpenCode: delete the `bun install -g opencode-ai` block. Same pattern under `# renovate: datasource=github-releases depName=anomalyco/opencode extractVersion=^v(?<version>.+)$`, from `https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/<asset>`, installing `opencode` into `/usr/local/bin`.
- Claude Code: keep the Bun install block; bump the version.
- Write the hash `ARG`s with 64 zeros, set the versions per Global Constraints, then run `uv run scripts/bake_hashes.py` to fill them in.

- [ ] **Step 4: Build and run**

Run: `docker buildx bake core && uv run pytest images/core -v`
Expected: PASS.

- [ ] **Step 5: Prove a wrong hash fails the build (Review Focus 5)**

Run: `docker buildx bake core --set core.args.UV_SHA256_AMD64=$(printf '0%.0s' $(seq 64)) --set core.args.UV_SHA256_ARM64=$(printf '0%.0s' $(seq 64))`
Expected: the build FAILS at the `uv` step with a `sha256sum` mismatch. Repeat with the `OPENCODE_` pair.

- [ ] **Step 6: Commit**

```sh
git add -A && git commit -m "Recreate dev with bash and take uv and OpenCode 2 from hashed release archives"
```

---

### Task 4: Image rules: nothing self-updates, bare agents, git credentials, bare homes

**Files:**
- Modify: `images/core/Dockerfile`, `images/core/test_core.py`

**Interfaces:**
- Consumes: `plain`, `image`, `run_container` (Task 1).

The expected strings below are what PR 18's smoke test matched (`git show pr-18:images/core/smoke.sh`), where Claude Code was a native binary. If a tool's wording for the same state differs here, match the wording you observe. Never loosen a check so that a non-empty or updating state would pass.

- [ ] **Step 1: Write the failing tests**

```python
USERS = ["root", "dev"]

def test_homes_hold_only_shell_startup_files(image): ...
    # A fresh `docker run --rm` (not `plain`, which other tests have written to):
    # find /root /home/dev -mindepth 1 -maxdepth 1 lists only .bashrc, .profile, .bash_logout

@pytest.mark.parametrize("user", USERS)
@pytest.mark.parametrize("var", ["GH_TOKEN", "GITHUB_TOKEN"])
def test_git_gets_a_credential_through_gh(plain, user, var): ...
    # printf 'protocol=https\nhost=github.com\n\n' | GIT_TERMINAL_PROMPT=0 timeout 20 git credential fill
    # with env {var: "t-" + var}: stdout has the line "password=t-<var>"
@pytest.mark.parametrize("user", USERS)
def test_git_fails_without_a_token_and_does_not_prompt(plain, user): ...   # non-zero, within the timeout
def test_gist_host_uses_gh_too(plain): ...   # same fill with host=gist.github.com

@pytest.mark.parametrize("user", USERS)
def test_claude_is_bare(plain, user): ...
    # claude mcp list -> "No MCP servers configured"; claude plugin list -> "No plugins installed";
    # claude auth status -> '"loggedIn": false'
@pytest.mark.parametrize("user", USERS)
def test_opencode_is_bare(plain, user): ...
    # timeout 60 opencode --standalone mcp list -> "No MCP servers configured";
    # ... plugin list -> "No plugins found"; ... auth list -> "No authenticated integrations"

@pytest.mark.parametrize("how", ["root", "dev", "login"])
def test_claude_refuses_to_update(plain, how): ...
    # "login" runs the command through `su -l dev -c`. timeout 60 claude update -> "Updates are disabled"
@pytest.mark.parametrize("how", ["root", "dev", "login"])
def test_opencode_skips_its_update_check(plain, how): ...
    # cd /tmp && timeout 8 script -qec "opencode --standalone --print-logs 2>&1" /dev/null </dev/null
    # -> 'message="update check skipped" reason=disabled'
def test_claude_refuses_to_update_with_an_empty_environment(plain): ...
    # env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=/root claude update -> "Updates are disabled"
```

- [ ] **Step 2: Run to see them fail**

Run: `uv run pytest images/core -v`
Expected: the credential and self-update tests FAIL.

- [ ] **Step 3: Change the Dockerfile**

- `ENV DISABLE_AUTOUPDATER=1 DISABLE_UPDATES=1 OPENCODE_DISABLE_AUTOUPDATE=1`
- `/etc/claude-code/managed-settings.json` with an `env` object holding `DISABLE_AUTOUPDATER` and `DISABLE_UPDATES`, both `"1"`.
- Append the three variables to `/etc/environment`. No `/etc/environment.d` file: that is for the core systemd image.
- For `github.com` and `gist.github.com`: `git config --system credential.https://<host>.helper ''`, then `--add` the value `!/usr/bin/gh auth git-credential`.
- Check nothing in the build wrote under `/root` or `/home/dev`; remove what did, in the same `RUN` that created it.

- [ ] **Step 4: Build and run**

Run: `docker buildx bake core && uv run pytest images/core -v`
Expected: PASS. If a Claude Code test cannot pass with the Bun install, stop and ask Anton (Global Constraints).

- [ ] **Step 5: Commit**

```sh
git add -A && git commit -m "Turn self-updating off, wire gh as git's credential helper, keep the homes bare"
```

---

### Task 5: `start-docker` and the engine tests

**Files:**
- Modify: `images/core/start-docker`, `images/core/conftest.py`
- Create: `images/core/test_engine.py`

**Interfaces:**
- Consumes: `run_container`, `Container`, `image`, `inner_image` (Task 1).
- Produces: session fixture `engine -> Container` in `images/core/conftest.py`: a `--privileged` container in which `start-docker` has already returned 0 (the fixture asserts this, printing the script's output on failure). If the environment variable `GHCR_TOKEN` is set, the fixture logs the inner engine in to `ghcr.io` with `docker login --password-stdin`; otherwise it pulls anonymously. It then pulls `inner_image`.
- Produces: the environment variable `START_DOCKER_TIMEOUT` (seconds, default 60), replacing `START_DOCKERD_TIMEOUT`.

- [ ] **Step 1: Write the failing tests**

`test_engine.py` starts with `pytestmark = pytest.mark.privileged`.

```python
def test_engine_answers(engine): ...                      # docker info exits 0
def test_second_call_keeps_the_same_daemon(engine): ...   # /run/docker.pid is unchanged after start-docker as root and as dev
def test_dev_uses_the_engine_without_sudo(engine, inner_image): ...   # docker run --rm as dev prints "Hello from Docker!"
def test_container_with_a_memory_limit_runs(engine, inner_image): ... # docker run --rm --memory 64m exits 0
def test_docker_storage_is_a_mount(engine): ...           # findmnt /var/lib/docker exits 0
def test_log_is_appended(engine): ...                     # write a marker line to /var/log/dockerd.log, run start-docker, marker survives

def test_refuses_overlay_storage(image): ...
    # own privileged container: `umount /var/lib/docker && start-docker` exits non-zero
    # and stderr contains "mount a volume at /var/lib/docker"
def test_timeout_stops_the_daemon_it_started(image): ...
    # own privileged container: START_DOCKER_TIMEOUT=0 start-docker exits 1;
    # then `pgrep -x dockerd` finds nothing; then a plain start-docker exits 0
def test_concurrent_first_calls_start_one_daemon(image): ...   # Review Focus 1
    # own privileged container: `start-docker & start-docker & wait` then `pgrep -xc dockerd` prints 1
```

One test of this group needs no privilege, so it goes in `test_core.py`:

```python
def test_start_docker_fails_within_its_timeout_when_unprivileged(image): ...
    # own plain container: START_DOCKER_TIMEOUT=5 start-docker exits non-zero in under 30 s,
    # and `pgrep -x dockerd` finds nothing
```

- [ ] **Step 2: Run to see them fail**

Run: `uv run pytest images/core -v`
Expected: FAIL. Today's script still reads `START_DOCKERD_TIMEOUT`, overwrites its log, cannot run a memory-limited container, and leaves `dockerd` behind on timeout.

- [ ] **Step 3: Replace the script**

`git show pr-18:images/core/start-docker > images/core/start-docker`, keep it executable, then add the one fix: remember the PID when this run launches `dockerd`, and in the timeout branch, if that PID is set, send it `TERM` and wait for it to exit before `exit 1`. A daemon this run did not launch (the systemd path, or one already running under the lock) is left alone.

- [ ] **Step 4: Build and run everything**

Run: `docker buildx bake core && uv run pytest -v`
Expected: PASS, including `scripts`. Then `uv run pytest -m "not privileged" -v` to confirm the marker deselects exactly `test_engine.py`.

- [ ] **Step 5: Commit**

```sh
git add -A && git commit -m "Take start-docker from PR 18 and stop the daemon on timeout"
```

---

### Task 6: Pipeline

**Files:**
- Modify: `.github/workflows/build.yml`
- Create: `.github/workflows/pr-cleanup.yml`, `.github/workflows/lint.yml`, `.hadolint.yaml`

**Interfaces:**
- Consumes: `uv run pytest` (Tasks 1 to 5); `GHCR_TOKEN` (Task 5); `ARG UV_VERSION` (Task 3).
- Produces: checks `build (amd64)`, `build (arm64)`; tags `ghcr.io/plume-works/core:pr-<N>` and `:edge`.

- [ ] **Step 1: Rewrite `build.yml`**

Keep its triggers, top-level permissions, concurrency block and matrix. Add a workflow-level `PUBLISH` value, as in `git show pr-18:.github/workflows/images.yml`: true for a pull request whose head repo is this repo, and for a non-pull-request run on `refs/heads/main`; false otherwise.

`build` job steps, in order:

1. Checkout.
2. `docker/setup-buildx-action`.
3. Read `UV_VERSION` from `images/core/Dockerfile` into a step output; `astral-sh/setup-uv` with that `version`.
4. Build and load with `docker/bake-action` (`source: .`, target `core`), with `cache-from` and `cache-to` of `type=gha` scoped per architecture (`scope=core-<arch>`, `mode=max`). Keep its `metadata` output.
5. `uv run pytest`, with `GHCR_TOKEN` set to `github.token` only when `PUBLISH` is true.
6. If `PUBLISH`: log in to GHCR, then bake again with the same cache settings, `tags=ghcr.io/plume-works/core` and `output=type=image,push-by-digest=true,name-canonical=true,push=true`.
7. If `PUBLISH`: fail unless `containerimage.config.digest` is non-empty in both metadata outputs and equal. Print both values.
8. If `PUBLISH`: upload the pushed `containerimage.digest` as artifact `digest-<arch>`.

Replace the `manifest` job with `publish`: `needs: build`, same `PUBLISH` condition, `packages: write`. It downloads both digests and runs one `docker buildx imagetools create -t ghcr.io/plume-works/core:<tag>` with both, where `<tag>` is `pr-<number>` for a pull request and `edge` otherwise. No commit-SHA tag.

- [ ] **Step 2: Write `pr-cleanup.yml`**

From `git show pr-18:.github/workflows/pr-cleanup.yml`, cut to one package: on `pull_request: closed`, same-repo only, `dataaxiom/ghcr-cleanup-action` with `packages: core`, `delete-tags: pr-<number>`, `exclude-tags: edge`, concurrency group `ghcr-cleanup`.

- [ ] **Step 3: Write `lint.yml` and `.hadolint.yaml`**

Triggers: pull requests, pushes to `main`, manual. Three jobs: hadolint (recursive over files named `Dockerfile`, `failure-threshold: info`), shellcheck on `images/core/start-docker`, actionlint (it reads the existing `.github/actionlint.yaml`). Linter images are referenced as `docker://<image>:<version>@sha256:<digest>`. `.hadolint.yaml` ignores `DL3008` only (apt packages float by design).

- [ ] **Step 4: Run the linters locally and fix what they find**

```sh
docker run --rm -v "$PWD:/w" -w /w hadolint/hadolint hadolint --failure-threshold info images/core/Dockerfile
docker run --rm -v "$PWD:/w" -w /w koalaman/shellcheck-alpine shellcheck images/core/start-docker
docker run --rm -v "$PWD:/w" -w /w rhysd/actionlint -color
```

Expected: all three exit 0. A finding is fixed in the file, not ignored, unless the spec requires the flagged behaviour; record any ignore as a dismissed finding.

- [ ] **Step 5: Rebuild, retest, commit**

Run: `docker buildx bake core && uv run pytest -v` (lint fixes may have touched the Dockerfile or the script). Expected: PASS.

```sh
git add -A && git commit -m "Publish pr-N and edge only when the pushed image is the tested one; add lint and cleanup"
```

---

### Task 7: Renovate

**Files:**
- Modify: `renovate.json` (root; replace the hosted app's default)
- Delete: `.github/renovate.json`
- Create: `.github/workflows/renovate.yml`

**Interfaces:**
- Consumes: `uv run scripts/bake_hashes.py` (Task 2); `ARG UV_VERSION` (Task 3).
- Requires from Anton: secrets `RENOVATE_APP_CLIENT_ID` and `RENOVATE_APP_PRIVATE_KEY`.

Reference: clone `https://github.com/plume-works/agent-devcontainer` and read `.github/workflows/renovate.yml` and `.github/renovate.json`. Check each Renovate option used below against Renovate's docs for the version you pin; do not rely on memory for option names.

- [ ] **Step 1: Write the root `renovate.json`**

Start from `.github/renovate.json` and change only this:

- Remove the `customManagers` block (the `uv` regex manager) and the two package rules for `ghcr.io/astral-sh/uv`.
- Add `"matchDatasources": ["docker"]` to the Ubuntu major/minor hold.
- Extend the preset that reads `# renovate:` comments above `VERSION` lines in workflow files (`customManagers:githubActionsVersions`), for the Renovate pin in Step 2.
- Add a package rule matching dep names `astral-sh/uv` and `anomalyco/opencode` with `postUpgradeTasks`: command `uv run scripts/bake_hashes.py`, `fileFilters` `["images/core/Dockerfile"]`, `executionMode` `"branch"`.

Keep: `config:recommended`, `docker:pinDigests`, `helpers:pinGitHubActionDigests`, `customManagers:dockerfileVersions`, the 3-day wait, the 10-day rule for `.0`, automerge for everything. Then `git rm .github/renovate.json`.

- [ ] **Step 2: Write `renovate.yml`**

- Triggers: `schedule` (daily), `push` to `main`, `workflow_dispatch`. No issue or pull-request-edit triggers.
- One job on `ubuntu-26.04`, no container, with job-level concurrency `group: ${{ github.workflow }}`, `cancel-in-progress: false`, and a 60-minute timeout.
- Steps: checkout; `oven-sh/setup-bun`; `astral-sh/setup-uv` at the Dockerfile's `UV_VERSION` (as in Task 6); `actions/create-github-app-token` with the two secrets and the same permission list as the reference; resolve the App's commit identity as the reference does; run `bunx --package "renovate@${RENOVATE_VERSION}" renovate`.
- `RENOVATE_VERSION` is a workflow `env` value under a `# renovate: datasource=npm depName=renovate` comment, set to the newest release at least 3 days old.
- Environment for the run: `RENOVATE_TOKEN`, `RENOVATE_PLATFORM: github`, `RENOVATE_REPOSITORIES: ${{ github.repository }}`, `RENOVATE_ONBOARDING: 'false'`, `RENOVATE_REQUIRE_CONFIG: required`, `RENOVATE_GIT_AUTHOR`, `LOG_LEVEL: info`, and `RENOVATE_ALLOWED_COMMANDS: '["^uv run scripts/bake_hashes\\.py$"]'`.
- Pass the App token to the post-upgrade command as `GITHUB_TOKEN`. Renovate gives child commands only a short fixed list of variables, and anonymous API calls from shared runner addresses hit the rate limit. Route it through `secrets`, as Renovate's docs require for secret values, and do not use `exposeAllEnv`:

  ```yaml
  RENOVATE_SECRETS: '{"APP_TOKEN": "${{ steps.app-token.outputs.token }}"}'
  RENOVATE_CUSTOM_ENV_VARIABLES: '{"GITHUB_TOKEN": "{{ secrets.APP_TOKEN }}"}'
  ```

  This pairing set through environment variables is unverified until a real Renovate run; list it in Task 9's report.

- [ ] **Step 3: Validate**

```sh
docker run --rm -v "$PWD:/w" -w /w ghcr.io/plume-works/core:edge \
  bunx --package renovate@<RENOVATE_VERSION> renovate-config-validator --strict renovate.json
docker run --rm -v "$PWD:/w" -w /w rhysd/actionlint -color
```

Expected: the validator reports the config valid; actionlint exits 0.

- [ ] **Step 4: Dry-run the post-upgrade command by hand**

In `images/core/Dockerfile`, set `UV_SHA256_AMD64` to 64 zeros, run `uv run scripts/bake_hashes.py`, and check `git diff` is empty (the script restored the real hash).

- [ ] **Step 5: Commit**

```sh
git add -A && git commit -m "Run Renovate in Actions as the plume-works-renovate App, baking hashes on each bump"
```

---

### Task 8: Docs

Use the `domain-modeling` skill for every ADR and for the glossary.

**Files:**
- Modify: `docs/adr/0006-opt-in-docker-daemon.md`, `docs/adr/0008-shared-dev-user.md`, `docs/adr/0009-renovate-release-wait.md`, `README.md`
- Create: `docs/adr/0011-*.md`, `docs/adr/0012-*.md`, `GLOSSARY.md`
- Delete: `docs/handoff.md`

- [ ] **Step 1: ADRs**

- **0006:** the script is named `start-docker`.
- **0008, rewritten:** root is the image's default user (GitHub Actions job containers expect it); `dev` is created fresh at uid and gid 1000 with bash and passwordless sudo; fish is installed but nobody's default. The stock `ubuntu` user is deleted, not renamed.
- **0009:** drop the paragraph on the `uv` two-step workaround; `uv` now takes its version from GitHub releases directly.
- **0011, nothing under a home directory, nothing updates itself:** a home volume is filled from the image only once, so anything there freezes and shadows newer images; a version changes only through a tested pull request. Name the three places self-update is turned off.
- **0012, self-hosted Renovate and baked hashes:** archives are checked against a sha256 committed here; a checksum fetched from the same server at build time protects against nothing; the post-upgrade script takes the hash GitHub recorded and refuses a release that is not immutable. State that this reverses issue 4 (hosted app, no custom scripts). State the two deliberate exceptions: vendor apt repos fetch their signing key at build time, and Claude Code from npm has no hash here, protected by its exact version and the 3-day wait.

- [ ] **Step 2: `GLOSSARY.md`**

One term, **Core image**, with PR 18's definition and avoid-list (`git show pr-18:GLOSSARY.md`). No other terms.

- [ ] **Step 3: README**

Keep it brief. Update: paths and commands (`docker buildx bake core`, `uv run pytest`, `-m "not privileged"`, `--image`), `start-docker`, the `pr-N` and `edge` tags, one short paragraph on how versions update, and the admission rule: a build toolchain is added to the core image only when at least two plume-works repositories need it in CI; interactive conveniences are added at the maintainer's discretion. Point the design link at the 2026-11-19 spec.

- [ ] **Step 4: Check every `docs/handoff.md` item, then delete it**

Go through the file section by section. Each item must be done on this branch, listed in the spec's "For Anton to do" or "Not verified" sections, or in the dismissed-findings record. Then `git rm docs/handoff.md`.

- [ ] **Step 5: Commit**

```sh
git add -A && git commit -m "Record the user, home and Renovate decisions; add the glossary; retire the handoff"
```

---

### Task 9: Final check, push, report

- [ ] **Step 1: Full local run from a clean build**

```sh
docker buildx bake core --no-cache && uv run pytest -v
grep -rn "start-dockerd\|core/test.sh\|START_DOCKERD" --exclude-dir=.git --exclude-dir=transcripts --exclude-dir=docs/superpowers . 
```

Expected: all tests pass; the grep finds nothing.

- [ ] **Step 2: Push and watch CI**

Push the branch (PR 2 is open on it). Expected on the pull request: `build (amd64)`, `build (arm64)` and the three lint jobs green; `publish` creates `ghcr.io/plume-works/core:pr-2`. Verify with `docker buildx imagetools inspect ghcr.io/plume-works/core:pr-2` that it lists `linux/amd64` and `linux/arm64`. Fix what fails and push again.

- [ ] **Step 3: Write the final report to Anton**

It contains, in this order:

1. What was built, and the test and CI results as observed.
2. **Every dismissed finding** from this build's reviews, plus the two carried in (see Global Constraints), each with who dismissed it and why, so Anton can overrule.
3. What only Anton can do:
   - require `build (amd64)` and `build (arm64)` on `main`
   - install the `plume-works-renovate` App on this repo and add `RENOVATE_APP_CLIENT_ID` and `RENOVATE_APP_PRIVATE_KEY`
   - remove the hosted Renovate app from this repo
   - make the `core` package public after the first publish
   
   (The `hello-world` mirror is already in place and public; verified 2026-11-19.)
4. What is still unverified: the `edge` publish path until the first merge to `main`, and a real Renovate run including the post-upgrade command.
