# Root is the default user; dev is created fresh

The core image runs as root, because GitHub Actions job containers expect that. It also has one shared non-root
user, `dev`, created at uid and gid 1000 with bash as its shell and passwordless sudo, so every image built on it
has the same home, shell and file ownership. fish is installed but nobody's default shell.

The base image's stock `ubuntu` user also holds uid and gid 1000. It is deleted, not renamed, so nothing of it
(home directory, subordinate IDs, sudoers entry) is left behind to carry over.
