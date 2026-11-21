#!/usr/bin/env bash
# Print every image of the bake file's default group, one per line, parent first.
#
# The one list of images that CI (images.yml, ghcr-cleanup.yml) works from. The order comes from the bake file's
# own parent links (a `contexts` entry "target:<parent>"), not from the group: `bake --print` sorts the group
# alphabetically. An image comes after its parent; images at the same depth come in name order.
set -euo pipefail

docker buildx bake -f images/docker-bake.hcl --print "$@" 2>/dev/null | jq -r '
  .target as $targets
  | def parents($t): [($targets[$t].contexts // {})[] | strings | select(startswith("target:")) | ltrimstr("target:")];
    # Depth below the root image; $seen stops a cycle (which bake would reject anyway).
    def depth($t; $seen):
      if ($seen | index([$t])) then error("parent cycle through \($t)")
      else ([parents($t)[] | depth(.; $seen + [$t]) + 1] | max) // 0 end;
  .group.default.targets
  | map({name: ., depth: depth(.; [])})
  | sort_by(.depth, .name)
  | .[].name'
