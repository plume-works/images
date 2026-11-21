#!/bin/sh
# Shellcheck every shell script in the repository. Scripts are found by shebang, so extension-less ones count.
# Runs in koalaman/shellcheck-alpine (busybox, no git): see .github/workflows/lint.yml.
set -eu

find . -path ./.git -prune -o -type f -print |
  while read -r f; do
    if head -n1 "$f" | grep -qE '^#!.*[/ ](ba|da)?sh( |$)'; then
      echo "$f"
    fi
  done |
  xargs -r shellcheck --external-sources
