# Images repo

`README.md` states the repo purpose. Keep it current as the repo evolves, and brief: durable knowledge belongs in ADRs and `GLOSSARY.md`, not the README.

## Design principles

YAGNI, KISS, DRY.

YAGNI, KISS, DRY.

YAGNI, KISS, DRY.

## Local temporary files

Use gitignored .tmp in the repo root for your temporary files, so you can clean them up once done.

## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues on `plume-works/images`, through the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Uses the five default triage labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` at the repo root and ADRs in `docs/adr/`. Record decisions and glossary terms with the `domain-modeling` skill.

@docs/agents/domain.md

## Reviews

Log every finding a reviewer dismissed, and end the task with a report of them for a human to review.
