# Claude remote control: Anthropic token variables kept back, its consent prompt answered

Two deliberate exceptions in the Coder template image's `claude-remote-control.service` that a reader would otherwise "fix".

**The Anthropic token variables do not reach it.** ADR 0002 hands every variable of the agent's environment, so every Coder secret, to every agent service. This unit removes three of them (`UnsetEnvironment=ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_OAUTH_TOKEN`). Claude remote control works only with a claude.ai subscription sign-in and refuses to start while an API key or a long-lived token is set, so a user who defines one of these as a Coder secret for terminal use would silently lose remote control. We kept the whole-environment import (a named list would bring back template edits for every new secret) and keep back exactly the variables known to stop remote control, in this one unit only. Every other variable, and every variable for OpenCode, still arrives.

**Its one-time consent question is answered by the unit.** On first start, remote control asks "Enable Remote Control? (y/n)" on its input and records the answer in the user's home. The unit feeds it `y` (`StandardInputText=y`): enabling the service is the consent, and without a terminal nothing else could answer, so the service would never start. Workspace trust, by contrast, is deliberately not pre-granted: it is a per-repository security decision the user makes once by running `claude` in the repository, together with `/login`. Until then the unit exits at once and systemd keeps restarting it.

## Consequences

- If Claude Code starts rejecting another variable, it is added to this unit's list, not removed from the import.
- If the consent question changes wording or position (another question before it), the fixed `y` may answer the wrong question; the Coder template image's smoke test only proves the unit keeps retrying without a sign-in, so a Claude Code bump must be checked by hand with a signed-in workspace.
