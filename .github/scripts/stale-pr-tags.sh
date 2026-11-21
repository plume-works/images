#!/usr/bin/env bash
# Print, comma-separated, every pr-N tag that one of the given images carries for a pull request closed (merged
# or not) at least DAYS days ago. Prints nothing if there is none.
#
# Needs gh with read access to the organization's container packages and to the repository's pull requests;
# the repository is gh's (GH_REPO, or the git remote), and its owner owns the packages.
# Works from the tags that exist, not from the closed pull requests, so its work does not grow with history,
# and a pr-N that a late publish put back after the pull request closed is found too.
set -euo pipefail

days=${1:?usage: $0 DAYS IMAGE...}
shift
[ "$#" -gt 0 ] || { echo "usage: $0 DAYS IMAGE..." >&2; exit 2; }
cutoff=$(date -u -d "-$days days" +%s)

numbers=$(
  for img; do
    gh api --paginate "/orgs/{owner}/packages/container/$img/versions" --jq '.[].metadata.container.tags[]'
  done | sed -n 's/^pr-\([0-9][0-9]*\)$/\1/p' | sort -un
)

for n in $numbers; do
  closed=$(gh pr view "$n" --json closedAt --jq '.closedAt // empty')
  if [ -n "$closed" ] && [ "$(date -u -d "$closed" +%s)" -le "$cutoff" ]; then
    echo "pr-$n"
  fi
done | paste -sd, -
