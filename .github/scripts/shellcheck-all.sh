#!/bin/sh
# Shellcheck every shell script in the repository. Scripts are found by shebang, so extension-less ones count.
# Runs from the repository root, in koalaman/shellcheck-alpine (busybox, no git): see .github/workflows/lint.yml.
# Exits non-zero on any finding.
set -eu

find . -path ./.git -prune -o -type f -print |
  while read -r f; do
    if head -n1 "$f" | grep -qE '^#!.*[/ ](ba|da)?sh( |$)'; then
      echo "$f"
    fi
  done |
  xargs -r shellcheck --external-sources
