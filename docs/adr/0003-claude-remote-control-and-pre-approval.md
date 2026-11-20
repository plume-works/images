# Claude remote control: Anthropic tokens kept back, Claude pre-approval on by default

Two deliberate choices about Claude in a Coder workspace that a reader would otherwise "fix".

**The Anthropic tokens do not reach remote control.** ADR 0002 hands every Coder secret to every agent service.
Claude remote control works only with a claude.ai subscription sign-in and refuses to start while an Anthropic API
key or long-lived token is set, so a user who defines one as a Coder secret for terminal use would silently lose
remote control. We keep the whole-environment import and keep back exactly the token variables known to stop
remote control, from remote control only.

**Claude pre-approval is on by default.** When a workspace is created, its user chooses two approvals, both on by
default: the one-time consent to Claude remote control, and trust in the cloned repository (its project MCP
servers included). A Coder workspace is a sandbox, so only a
workspace for really untrusted code needs either off. The choice is made once, at creation, and only grants:
nothing is ever revoked.

## Considered options

- **Answer the consent on remote control's behalf, but leave trust to the user**, the previous version of this
  decision. Rejected: remote control did nothing until the user had run Claude by hand in the repository, and in
  a sandbox the trust prompt protects little.
- **Both off by default.** Rejected for the same reason: the sandbox is the protection.
- **Changeable after creation, with switching off revoking what was granted.** Rejected as more than is needed.

## Consequences

- If Claude Code starts rejecting another token variable, it is kept back from remote control too, not removed
  from the import.
