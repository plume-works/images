# Claude pre-approval on by default

When a Coder workspace is created, its user chooses two approvals, both on by default: the one-time consent to
Claude remote control, and trust in the cloned repository, together with approval of the project MCP servers of
every project in the workspace. The choices are workspace-wide, because the workspace is the sandbox: only trust
itself names the cloned repository, and nothing narrows the rest to it. So only a workspace for really untrusted
code needs either off. The choice is made once, at creation, and only grants: nothing is ever revoked.

## Considered options

- **Answer the consent on remote control's behalf, but leave trust to the user**, the previous decision (in ADR
  0003). Rejected: remote control did nothing until the user had run Claude by hand in the repository, and in a
  sandbox the trust prompt protects little.
- **Both off by default.** Rejected for the same reason: the sandbox is the protection.
- **Approve MCP servers for the cloned repository only.** Rejected: the workspace, not the repository, is the
  sandbox, and other projects in it would ask again for nothing.
- **Changeable after creation, with switching off revoking what was granted.** Rejected as more than is needed.
