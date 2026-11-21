#!/usr/bin/env bash
# Works from existing tags, not closed pull requests: cost does not grow with history, and a pr-N a late
# publish put back is found too.
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
