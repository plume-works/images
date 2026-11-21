#!/bin/sh
# Found by shebang, so extension-less scripts count. Runs in shellcheck-alpine: busybox, no git.
set -eu

find . -path ./.git -prune -o -type f -print |
  while read -r f; do
    if head -n1 "$f" | grep -qE '^#!.*[/ ](ba|da)?sh( |$)'; then
      echo "$f"
    fi
  done |
  xargs -r shellcheck --external-sources
