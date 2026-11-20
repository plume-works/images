# Agent services run inside tmux

Agent services are interactive apps, and one that is stuck is usually stuck on its screen: a prompt, a sign-in, a
status it keeps redrawing. Each agent service therefore runs its app inside its own tmux server, named after the
service, so anyone in the workspace can attach and see exactly what the app shows. systemd stays the only
supervisor (ADR 0001): tmux lives and dies with the app, and the app's exit is the service's exit.

The journal does not get the app's live output, only its last screen when it exits. Remote control redraws its
status about once a second, so its live output in the journal was about 45 MB a day of repeated lines, burying
the few that matter.

## Considered options

- **No tmux, the journal only.** Rejected: an app waiting on its screen shows nothing useful there, and its
  redraws flood it.
- **Every line of the pane also in the journal.** Rejected for the same flood, made worse by a real terminal.
- **tmux as the supervisor**, as in plume-works/agent-devcontainer, where a watcher restarts a vanished session.
  Rejected: it would be a second supervisor beside systemd.
