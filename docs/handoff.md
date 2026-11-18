# Handoff: continuing the core image

Written 2026-11-18. The core image was built four times on four branches, to compare ways of
working. This branch, the second attempt, is the one being carried forward. This note is what a
new session needs to pick it up. "Attempt 3" below is the branch `core-images-try3-no-ssd`, built
from the same spec and plan.

## Where it is

- **Branch:** `core-images-try2`; this note was written against `302cc8a`
- **PR:** https://github.com/plume-works/images/pull/2, open, CI green on amd64 and arm64
- **Read first, in the clone:** `docs/superpowers/specs/2026-11-17-core-image-design.md` and
  `docs/adr/`. The plan under `docs/superpowers/plans/` is a finished execution script and is
  stale (it still says `ubuntu-24.04` runners); do not work from it.
- **Session transcripts:** `transcripts/` in the clone, untracked.

What exists: one `core` image (`core/Dockerfile`, `core/start-dockerd`, `core/test.sh`), a bake
file, a build-and-publish workflow, a Renovate config, a README and eight short ADRs.

## Must do before or with the merge

1. **Remove `renovate.json` from the root of `main`.** Renovate's onboarding PR #19 was merged, so
   `main` now holds a default `renovate.json`. Renovate reads the root file before
   `.github/renovate.json`, so after a merge this branch's config would be silently ignored.
   Delete the root file on this branch (after merging or rebasing on `main`).
2. **Require the two build checks on `main`.** `main` has no branch protection, and auto-merge is
   already allowed on the repo. The Renovate config automerges everything, so without required
   `build (amd64)` and `build (arm64)` checks its PRs merge at once, untested.

## Known defects, not yet fixed

Reviewers saw the first two and closed them without showing them to the human.

- **`start-dockerd` leaves the daemon running on timeout.** It exits 1 but does not stop the
  `dockerd` it started, so a retry launches a second one.
- **`start-dockerd` overwrites its log on each start** (`>"$log"` at line 17).

Attempt 3 fixed both in commit `6071fc0` on `core-images-try3-no-ssd`; that script is a ready
reference (`git show origin/core-images-try3-no-ssd:core/start-dockerd`). Its fix is: stop the daemon when the timeout fires, and append to the log.

## Improvements attempt 3 has and this branch lacks

Each was approved by the human in attempt 3 ("all recommended"). Decide whether to port them.

- **Self-updates off.** `ENV DISABLE_AUTOUPDATER=1 OPENCODE_DISABLE_AUTOUPDATE=1`, so only
  Renovate moves the Claude Code and OpenCode versions.
- **User tool directories on `PATH`.** `/home/dev/.local/bin` and `/home/dev/.bun/bin`, where
  `uv tool install` and `bun add -g` put things. Attempt 3's reviewer rated the gap Important.
- **Subordinate IDs renamed.** `/etc/subuid` and `/etc/subgid` still name `ubuntu` after the user
  is renamed to `dev`.
- **Ubuntu hold scoped to Docker.** The rule with `matchDepNames: ["ubuntu"]` has no
  `matchDatasources: ["docker"]`, so it also blocks runner-label bumps.
- **Failure detail in tests.** Attempt 3's checks print what they saw (the uid, the login shell,
  the missing tool). This branch prints the output tail, which is often empty.

## Small leftovers

- `docker-bake.hcl` sets `org.opencontainers.image.version` to an empty string.
- The image still carries Ubuntu's `org.opencontainers.image.created` date.
- The spec lists `.dockerignore` at the repo root; it lives at `core/.dockerignore`.
- The comment above the "fails unprivileged" test says the script's timeout fires; in fact the
  daemon dies and the script stops early.
- The last two commits are a change and its revert (weekly Ubuntu digest schedule). Squash on
  merge, or drop both.
- `.gitignore` in the clone is untracked (it ignores `transcripts/`).

Reviewers also raised these and they were judged not worth fixing; listed so the call can be
overruled: `packages: write` is granted on PR builds; no check that a pushed digest is non-empty;
`docker info` calls are not time-bounded; a non-numeric `START_DOCKERD_TIMEOUT` gives no hint; CI
pulls `hello-world` anonymously.

## The `uv` update flow

A deliberate workaround, not a defect. GHCR gives no release dates, so under the 3-day wait `uv`
would never update. The human chose to read the version from GitHub releases while still copying
`uv` from its image. That takes a regex manager and two package rules in `.github/renovate.json`,
and two PRs per update:

1. The version text is bumped after the wait; the digest is unchanged.
2. The digest is repinned to the new version, with no wait.

Between the two, `main` shows the new version while still building the old `uv`, and CI on the
first PR tests nothing new. This flow has not been seen to run. Watch the first real `uv` update
and confirm the second PR appears.

## Never verified

- The publish path: the `manifest` job runs only on `main`. After the merge, check that
  `ghcr.io/plume-works/core:edge` lists both platforms and matches the commit-SHA tag.
- A real Renovate run against this config, including automerge and the 10-day wait for `x.y.0`
  releases.
- The `core` package's visibility on GHCR, to be set after the first publish.

## Decisions already made, do not reopen without cause

- Bun instead of Node; Claude Code and OpenCode installed with Bun at exact versions.
- No entrypoint or supervisor in `core`; the Docker daemon is opt-in through `start-dockerd`.
- `/var/lib/docker` is a declared volume.
- One shared user `dev`, uid and gid 1000, fish as login shell, passwordless sudo.
- Every update waits 3 days, `x.y.0` releases 10 days; the Ubuntu digest updates as soon as
  available (a weekly schedule was tried and withdrawn because it delays security fixes).
- CI runs on `ubuntu-26.04` runners.

## One process note

When using subagent-driven development again, ask for the final report to list every finding a
reviewer dismissed, so the human can overrule it. On this branch reviewers closed the two
`start-dockerd` defects above as out of scope, and the human never saw them.

Delete this file once its items are done or moved to issues.
