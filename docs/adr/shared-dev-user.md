# One shared user, dev

`core` has one non-root user, `dev` (uid and gid 1000, passwordless sudo, fish
as login shell), so every image built on it has the same home, shell and file
ownership. Proposed by Claude, confirmed by Anton.
