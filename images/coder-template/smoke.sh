#!/usr/bin/env bash
# Smoke test for the Coder template image.
#
# Boots the image with its own entrypoint in privileged mode (hosted runners have no sysbox), first as a
# plain container, then with the two files a Coder template uploads: a stand-in for the agent's init script
# and a token file. The stand-in does what the real agent and the template's startup script do (ADR 0002):
# hands its environment to dev's user manager and starts the agent-services target.
# It does not repeat the core systemd image's checks.
set -euo pipefail

image="${1:?usage: $0 <image-ref>}"
# shellcheck source=images/smoke-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../smoke-lib.sh"
smoke_init coder-template
work=$(mktemp -d "${TMPDIR:-/tmp}/coder-template-smoke.XXXXXX")

cleanup_extra() { rm -rf "${work:-}"; }
dump_extra() {
  as_dev systemctl --user status --no-pager agent-services.target opencode.service claude-remote-control.service
}
as_dev() { docker exec -u dev -e XDG_RUNTIME_DIR=/run/user/1000 "$container" "$@"; }

# Wait up to $1 seconds for a command to succeed, trying it every tenth of a second: often enough to catch a
# pane that lives only briefly.
wait_for() {
  local end=$((SECONDS + $1))
  shift
  until "$@" >/dev/null 2>&1; do
    [ "$SECONDS" -lt "$end" ] || return 1
    sleep 0.1
  done
}

# --- First boot: a plain container, nothing uploaded --------------------------------------------------------

boot
pass "the image boots to a running state with no failed units, without the template's uploads"

# The agent unit is enabled but skipped: without the init script there is nothing to run.
[ "$(in_container systemctl is-enabled coder-agent.service)" = enabled ] || fail "the Coder agent unit is not enabled"
! in_container systemctl is-active --quiet coder-agent.service || fail "the Coder agent runs without an init script"
for u in agent-services.target opencode.service claude-remote-control.service; do
  ! as_dev systemctl --user is-active --quiet "$u" || fail "$u is active although nothing started it"
done
pass "nothing starts the agent services at boot"

# --- Second boot: with the two files a Coder template uploads -----------------------------------------------

token="smoke-agent-token-$RANDOM$RANDOM"
var="smoke-imported-$RANDOM$RANDOM"
password="smoke-password-$RANDOM$RANDOM"

# A stand-in for coder_agent.init_script (a POSIX sh script). It records what the agent would see, then runs
# what the template's startup script runs: clone a repository (here: create one), then the hand-off.
# The imported variables stand for Coder user secrets and the template's agent variables, with both Claude
# pre-approval choices on. CLAUDE_CODE_OAUTH_TOKEN is a secret a user may well define for terminal use, and it
# would stop remote control.
cat >"$work/agent-init.sh" <<EOF
#!/usr/bin/env sh
set -eu
{ id -un; cat "\$CODER_AGENT_TOKEN_FILE"; } >/home/dev/agent-saw
git init -q /home/dev/repo
git -C /home/dev/repo -c user.name=smoke -c user.email=smoke@example.com commit -q --allow-empty -m init
export REPO_DIR=/home/dev/repo SMOKE_VAR=$var OPENCODE_PASSWORD=$password CLAUDE_CODE_OAUTH_TOKEN=smoke-not-a-token
export CLAUDE_PREAPPROVE_REMOTE_CONTROL=true CLAUDE_PREAPPROVE_TRUST_WORKSPACE=true
bash -c 'systemctl --user import-environment \$(compgen -e) && systemctl --user start agent-services.target'
echo started >>/home/dev/agent-saw
exec sleep infinity
EOF
printf '%s\n' "$token" >"$work/agent-token"

# A ~/.claude.json and a ~/.claude/settings.json (with a setting of the user's own) that link into a dotfiles
# checkout, which must stay links.
as_dev sh -c 'mkdir -p ~/dotfiles ~/.claude && echo "{\"smoke\": \"kept\"}" >~/dotfiles/claude.json &&
  echo "{\"model\": \"smoke\"}" >~/dotfiles/settings.json &&
  ln -sf dotfiles/claude.json ~/.claude.json && ln -sf ../dotfiles/settings.json ~/.claude/settings.json'

docker stop -t 60 "$container" >/dev/null
# Like the template's uploads: in place before the container starts, the token owned by dev and readable by
# dev only. (Tar streams, so owner and mode are the template's, not this machine's.)
tar -C "$work" -c --owner=0 --group=0 --mode=0755 agent-init.sh | docker cp -a - "$container:/etc/coder"
tar -C "$work" -c --owner=1000 --group=1000 --mode=0600 agent-token | docker cp -a - "$container:/etc/coder"
boot again

wait_for 60 as_dev grep -qx started /home/dev/agent-saw || fail "the Coder agent's startup did not complete"
[ "$(as_dev sed -n 1p /home/dev/agent-saw)" = dev ] || fail "the Coder agent does not run as dev"
[ "$(as_dev sed -n 2p /home/dev/agent-saw)" = "$token" ] || fail "the Coder agent did not read the token file"
pass "the Coder agent runs as dev, reads its token from the uploaded file and reaches dev's user manager"

as_dev systemctl --user is-active --quiet agent-services.target || fail "agent-services.target is not active"

# Claude pre-approval, both choices on: everything granted, the user's own setting kept.
# claude_has FILE FILTER: FILTER holds in /home/dev/FILE.
claude_has() { as_dev jq -e "$2" "/home/dev/$1" >/dev/null; }
claude_has .claude.json '.hasCompletedOnboarding == true' || fail "Claude's onboarding is not marked completed"
claude_has .claude.json '.remoteDialogSeen == true' || fail "remote control's consent is not granted"
claude_has .claude.json '.projects["/home/dev/repo"].hasTrustDialogAccepted == true' || fail "the repository is not trusted"
claude_has .claude.json '.projects["/home/dev/repo"] | has("enableAllProjectMcpServers") | not' ||
  fail "project MCP servers are approved for the repository only, not for the whole workspace"
claude_has .claude/settings.json '.enableAllProjectMcpServers == true and .model == "smoke"' ||
  fail "project MCP servers are not approved for the whole workspace, or the user's own setting is lost"
[ "$(as_dev readlink /home/dev/.claude.json)" = dotfiles/claude.json ] || fail "the symlinked ~/.claude.json is no longer a link"
[ "$(as_dev readlink /home/dev/.claude/settings.json)" = ../dotfiles/settings.json ] ||
  fail "the symlinked ~/.claude/settings.json is no longer a link"
claude_has dotfiles/claude.json '.smoke == "kept" and .hasCompletedOnboarding == true' ||
  fail "the symlinked ~/.claude.json's target lacks the approvals or its own key"
pass "with both Claude pre-approval choices on, onboarding, consent, trust and every project's MCP servers are granted"

# Each agent service runs its app in its own tmux server, on a socket named after its unit (ADR 0015).
# opencode_pid: the OpenCode server's PID, when it is the live process in the pane of socket opencode, and still
# in opencode.service (so systemd supervises and stops it).
opencode_pid() {
  local p pid
  p=$(as_dev tmux -L opencode display-message -p -t opencode '#{pane_dead} #{pane_pid}') && [ "${p% *}" = 0 ] ||
    return 1
  pid=${p#* }
  as_dev cat "/proc/$pid/cmdline" | tr '\0' ' ' | grep 'opencode serve' >/dev/null &&
    as_dev cat "/proc/$pid/cgroup" | grep '/opencode\.service$' >/dev/null && echo "$pid"
}
wait_for 60 opencode_pid || fail "the OpenCode server does not run in the pane of tmux socket opencode"
pid=$(opencode_pid)
# Remote control has no sign-in here, so it runs only briefly before each restart.
rc_pane() {
  as_dev tmux -L claude-remote-control display-message -p -t claude-remote-control '#{pane_start_command}' |
    grep 'claude remote-control' >/dev/null
}
wait_for 60 rc_pane || fail "remote control does not run in the pane of tmux socket claude-remote-control"
pass "each agent service runs its app in the pane of a tmux socket named after its unit"

as_dev cat "/proc/$pid/environ" | tr '\0' '\n' | grep -x "SMOKE_VAR=$var" >/dev/null ||
  fail "the imported variable did not reach the OpenCode server"
pass "a variable imported the ADR 0002 way reaches a service under agent-services.target"

opencode_info() { as_dev curl -fsS -u "opencode:$password" http://127.0.0.1:4096/api/info; }
wait_for 60 opencode_info || fail "the OpenCode server does not answer on localhost with the imported password"
[ "$(as_dev curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:4096/api/info)" = 401 ] ||
  fail "the OpenCode API answers without the password"
[ "$(as_dev curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:4096/)" = 200 ] ||
  fail "the OpenCode web UI does not answer on / (the Coder health check)"
pass "the OpenCode server answers on localhost, with the imported password guarding its API"

# Every listening TCP socket in the container is on a loopback address (the image has no ss; /proc/net/tcp
# holds addresses in hex: 127.x.x.x ends in 7F, ::1 is 0...01000000).
# shellcheck disable=SC2016 # awk's own $fields
nonlocal=$(in_container awk 'FNR > 1 && $4 == "0A" { split($2, a, ":"); print a[1] }' /proc/net/tcp /proc/net/tcp6 |
  grep -vxE '[0-9A-F]{6}7F|0{24}01000000' || true)
[ -z "$nonlocal" ] || fail "something listens on a non-loopback address: $nonlocal"
pass "the agent services listen on localhost only"

# A user attached without -r opens a window of their own, whose shell then exits: OpenCode's service must not end.
main_pid() { as_dev systemctl --user show -p MainPID --value opencode.service; }
main=$(main_pid)
as_dev tmux -L opencode new-window -d -- sh -c 'echo smoke-extra-window; exit 4'
sleep 3
untouched() { [ "$(main_pid)" = "$main" ] && [ "$(opencode_pid)" = "$pid" ] && opencode_info >/dev/null; }
untouched || fail "a pane other than the app's ending ended OpenCode's service"
pass "a pane other than the app's ending leaves the agent service running"

as_dev kill -9 "$pid"
restarted() {
  local p
  p=$(opencode_pid) && [ "$p" != "$pid" ] && opencode_info
}
wait_for 60 restarted || fail "the OpenCode server was not restarted in a new pane after being killed"
pass "a killed OpenCode server is restarted in a new pane, still with the imported environment"

# Remote control has no sign-in here, so it exits at once and must keep being restarted, without ever
# reaching a failed state. Its error, on the last screen the journal gets at each exit, shows the imported
# CLAUDE_CODE_OAUTH_TOKEN was kept from it: with the variable it would say a full-scope login token is required.
rc_restarts() { as_dev systemctl --user show -p NRestarts --value claude-remote-control.service; }
rc_retried() { [ "$(rc_restarts)" -ge 2 ]; }
wait_for 90 rc_retried || fail "remote control is not being restarted (restarts: $(rc_restarts))"
! as_dev systemctl --user is-failed --quiet claude-remote-control.service || fail "remote control gave up"
rc_log=$(as_dev journalctl --user -u claude-remote-control.service --no-pager -q -o cat)
grep -q 'You must be logged in to use Remote Control' <<<"$rc_log" ||
  fail "remote control did not stop for want of a sign-in: $(tail -n 5 <<<"$rc_log")"
! grep -q 'full-scope login token' <<<"$rc_log" || fail "remote control saw CLAUDE_CODE_OAUTH_TOKEN"
pass "remote control keeps retrying until a sign-in exists, without the API-token variables that stop it"

# The scrubber empties a prompt file written the way remote control writes one, in a session folder that did
# not exist when it started, and leaves the session's other files alone (ADR 0018).
as_dev systemctl --user is-active --quiet claude-bridge-prompt-scrub.service || fail "the prompt scrubber is not running"
session=/home/dev/.claude/bridge-spawn/smoke-session
as_dev sh -c "mkdir $session && echo cloud >$session/append-system-prompt.txt && echo '{}' >$session/mcp.json"
emptied() { [ "$(as_dev stat -c %s "$session/append-system-prompt.txt")" = 0 ]; }
wait_for 5 emptied || fail "the prompt scrubber did not empty a new session's prompt file"
[ "$(as_dev cat "$session/mcp.json")" = '{}' ] || fail "the prompt scrubber touched a session's other files"
pass "the prompt scrubber empties the cloud-container prompt of each new remote control session"

as_dev systemctl --user is-active --quiet agent-services.target || fail "agent-services.target stopped"
pass "the target stays up while its services restart"

# Remote control redraws its status about once a second once signed in, which needs a real sign-in. A stand-in
# agent service, through the same wrapper, redraws a status line in place, then exits with status 3.
# shellcheck disable=SC2016 # a script for the container's shell
as_dev systemd-run --user -q --unit smoke-redraw /usr/local/bin/run-in-tmux smoke-redraw sh -c '
  for i in $(seq 10); do printf "\033[1A\033[2Kstatus %s\n" "$i"; sleep 0.2; done
  echo stopping; exit 3'
redraw_done() { [ "$(as_dev systemctl --user show -p ActiveState --value smoke-redraw.service)" = failed ]; }
wait_for 30 redraw_done || fail "the stand-in agent service did not end"
[ "$(as_dev systemctl --user show -p ExecMainStatus --value smoke-redraw.service)" = 3 ] ||
  fail "the service does not report its app's exit status"
# What the service itself wrote, without systemd's own lines about it.
redraw_log=$(as_dev journalctl --user _SYSTEMD_USER_UNIT=smoke-redraw.service --no-pager -q -o cat)
[ "$redraw_log" = $'status 10\nstopping' ] ||
  fail "the journal does not hold exactly the app's last screen: $(head -n 20 <<<"$redraw_log")"
pass "an agent service's journal holds only its app's last screen, once, and the app's exit status"

# no_tmux NAME...: no tmux server answers on any of these sockets.
no_tmux() { for n in "$@"; do ! as_dev tmux -L "$n" list-sessions >/dev/null 2>&1 || return 1; done; }
no_tmux smoke-redraw || fail "the tmux server outlived its app"

# Claude pre-approval, both choices off: a fresh home's Claude files, and the hand-off again with the choices off,
# as a restarted workspace's startup script does it.
as_dev systemctl --user stop agent-services.target
no_tmux opencode claude-remote-control || fail "a tmux server outlived its stopped agent service"
pass "an agent service's tmux server ends with its app, or when the service stops"
as_dev rm -rf /home/dev/.claude.json /home/dev/.claude
as_dev systemctl --user set-environment CLAUDE_PREAPPROVE_REMOTE_CONTROL=false CLAUDE_PREAPPROVE_TRUST_WORKSPACE=false
as_dev systemctl --user start agent-services.target
claude_has .claude.json '.hasCompletedOnboarding == true' || fail "Claude's onboarding is not marked completed with both choices off"
claude_has .claude.json '.remoteDialogSeen != true' || fail "remote control's consent is granted although switched off"
claude_has .claude.json '.projects["/home/dev/repo"].hasTrustDialogAccepted != true' || fail "the repository is trusted although switched off"
! as_dev test -e /home/dev/.claude/settings.json || fail "Claude pre-approval created ~/.claude/settings.json"
pass "with both Claude pre-approval choices off, only onboarding is granted"

echo "coder-template smoke test passed: $image"
