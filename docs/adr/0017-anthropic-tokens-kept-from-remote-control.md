# Anthropic tokens kept back from Claude remote control

ADR 0002 hands every Coder secret to every agent service. Claude remote control works only with a claude.ai
subscription sign-in and refuses to start while an Anthropic API key or long-lived token is set, so a user who
defines one as a Coder secret for terminal use would silently lose remote control. We keep the whole-environment
import and keep back exactly the token variables known to stop remote control, from remote control only.

## Consequences

- If Claude Code starts rejecting another token variable, it is kept back from remote control too, not removed
  from the import.
