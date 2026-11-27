# Images repo

`README.md` states the repo purpose. Keep it current as the repo evolves, and brief: durable knowledge belongs in ADRs and `GLOSSARY.md`, not the README.

## Design principles

YAGNI, KISS, DRY.

YAGNI, KISS, DRY.

YAGNI, KISS, DRY.

## Code comments

A comment says why: a constraint, gotcha or rejected alternative the code cannot show. Never restate what the code, a step name or another comment already says. No file headers narrating the file.

## Scripts

Write scripts in Python 3 with the standard library only: the images' Python has no other packages. Shell stays for one-line commands in Dockerfiles, units and the Coder template, and for the `smoke.sh` tests.

Handle bad input without crashing: print an error naming what could not be done, carry on with the rest, and exit non-zero.

## Local temporary files

Use gitignored .tmp in the repo root for your temporary files, so you can clean them up once done.

## Credentials in tests

Delete a copied credential, and whatever holds it, as soon as the check finishes: a copied OAuth sign-in can renew and invalidate the original.

## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues on `plume-works/images`, through the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Uses the five default triage labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` at the repo root and ADRs in `docs/adr/`. Record decisions and glossary terms with the `domain-modeling` skill.
ADR is a Architecture DECISION RECORD, DO NOT PUT CODE IMPLEMENTATION DETAILS INTO IT EVER.

Delete superseded ADRs in the same PR that introduces replacement. List old decision under "Considered options".

@docs/agents/domain.md

## Reviews

Log every finding a reviewer dismissed, and end the task with a report of them for a human to review.

## PR

NEVER PUT DIFFS into PR body, description, comments.
NEVER LIST FILES into PR body, description, comments.
