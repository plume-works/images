# Smoke tests are pytest suites run through uv

Each image's smoke test is a pytest suite run with `uv`. The hard part is
driving containers from the host: boot systemd, stop and start again on the
same volumes, kill a service and wait for its restart. pytest's fixtures,
parametrised tests and flags already do what every bash attempt had to build
for itself. `uv` already ships in core and Renovate pins it; running the tests
needs it on the host next to Docker.

## Considered Options

- Bash (`smoke.sh` with a shared `smoke-lib.sh`): four attempts each grew their
  own framework for reporting, cleanup traps, polling, failure dumps and group
  selection.
- bats-core: standardises reporting but leaves JSON handling, polling and
  nested `sh -c` quoting as they were.
- Bun's test runner: the close second. It has no scoped fixtures or per-test
  failure hook.
- Go with testcontainers and Terratest: a toolchain nothing else here uses,
  and more code per check.
- Rust: no shared fixtures with teardown, and a killed test process skips
  cleanup.
- goss or container-structure-test: static checks only. They can't express
  boot, stop and restart.
