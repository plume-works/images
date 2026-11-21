# Remote control sessions drop the cloud-container prompt

Claude remote control appends, to every session it spawns on a workspace, a prompt written for Anthropic's cloud
containers ([anthropics/claude-code#100759](https://github.com/anthropics/claude-code/issues/100759)). It tells the
model the session runs in an ephemeral container, that `df` misleads and caches can be deleted to free space, and
that there is no `gh` CLI: only GitHub MCP tools that a workspace does not have, one repository, no `gh` but search.
On a workspace, where `gh` is signed in and `AGENTS.md` says to use it, that blocks the documented workflow.

The Coder template image's `claude-bridge-prompt-scrub.service` empties each session's
`~/.claude/bridge-spawn/<session>/append-system-prompt.txt` as soon as remote control writes it. Remote control also
hands the session the file's SHA-256, and the session drops a file that no longer matches, so the whole block is
dropped. The session reads the file about 90 ms after it starts; the scrubber reacts in under a millisecond. If it
ever misses, the prompt is used as before: it fails open.

## Considered options

- A wrapper around `/usr/local/bin/claude`: remote control starts sessions from its own resolved executable path, so
  a wrapper is bypassed.
- Patching the binary's JavaScript: it runs precompiled bytecode, so the edit has no effect.
- Overriding the hash with a settings `env`: applied after the file is checked.
- A FUSE mount over `bridge-spawn`: no `/dev/fuse` in the workspace container.

## Consequences

- Everything in that prompt goes, including the parts that are true; nothing else replaces it.
- When #100759 is fixed, the scrubber, its unit and this ADR are removed. A Claude Code bump that moves the file or
  drops the hash check is caught only by hand, with a signed-in workspace: the smoke test proves the scrubber, not
  what Claude Code does with an empty file.
