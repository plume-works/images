#!/usr/bin/env bash
# Print every image of the bake file's default group, one per line, parent first.
# Order comes from the `contexts` parent links: `bake --print` sorts the group alphabetically.
set -euo pipefail

docker buildx bake -f images/docker-bake.hcl --print "$@" 2>/dev/null | jq -r '
  .target as $targets
  | def parents($t): [($targets[$t].contexts // {})[] | strings | select(startswith("target:")) | ltrimstr("target:")];
    def depth($t; $seen):
      if ($seen | index([$t])) then error("parent cycle through \($t)")
      else ([parents($t)[] | depth(.; $seen + [$t]) + 1] | max) // 0 end;
  .group.default.targets
  | map({name: ., depth: depth(.; [])})
  | sort_by(.depth, .name)
  | .[].name'
