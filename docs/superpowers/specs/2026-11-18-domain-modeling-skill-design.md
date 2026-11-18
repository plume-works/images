# Adopt the domain-modeling skill

## Intent

The repo copied the ADR and glossary formats into its own files (`docs/adr/0000-adr-format.md`, `GLOSSARY-FORMAT.md`). We now vendor the upstream `domain-modeling` skill (mattpocock/skills) into `.agents/skills/domain-modeling/` and the agent domain-docs guide from the earlier attempt. The goal is one source of truth for the formats and no multi-context noise in a single-context repo.

## Goals

- ADR 0000 records the decision to use the skill and stops restating the format.
- The root `GLOSSARY-FORMAT.md` is deleted.
- `docs/agents/design.md` becomes `docs/agents/domain.md` (the name AGENTS.md already imports) and keeps only what applies to a single-context repo.
- Claude Code can invoke the skill.

## Non-goals

- Editing the vendored skill content. It stays an upstream copy, multi-context sections included; only the spec's `license` / `metadata` fields and a bundled `LICENSE.txt` are added.
- Writing `GLOSSARY.md` or new ADRs.

## Approaches

Ways to make the skill visible to Claude Code, which only scans `.claude/skills/`:

- **Symlink `.claude/skills` → `../.agents/skills`.** One copy, visible to Claude and to other agent tools. Chosen by the user.
- Move the skill into `.claude/skills/`. Simpler, but only Claude Code would find it.
- Leave it in place and point AGENTS.md at `SKILL.md`. It couldn't be invoked as a skill.

## Changes

- **Symlink:** create `.claude/skills` as a relative symlink to `../.agents/skills`.
- **Attribution in the skill, Agent Skills spec style** (https://agentskills.io/specification): `SKILL.md` frontmatter gets `license: MIT. LICENSE.txt has complete terms` and `metadata:` with `author: Matt Pocock` and `origin:` (upstream URL pinned to the commit the files match; the builder checks this against upstream). `git mv LICENSES/mattpocock-skills.txt .agents/skills/domain-modeling/LICENSE.txt` so the skill carries its own license. `LICENSES/` is then empty and goes away; the README license line drops its `LICENSES/` mention. `ADR-FORMAT.md` and `GLOSSARY-FORMAT.md` stay untouched (the skill-level license covers them).
- **ADR 0000** (`0000-adr-format.md` → `0000-domain-modeling-skill.md`): one paragraph recording this repo's choice. ADRs and the glossary follow the vendored `domain-modeling` skill rather than formats restated in the repo, so the formats change only by re-vendoring. No attribution here.
- **Delete** `GLOSSARY-FORMAT.md`.
- **ADR 0001:** replace "its format in `GLOSSARY-FORMAT.md`" with a pointer to the skill. Keep the YAGNI note that the skill's multi-context layout is unused here.
- **`docs/agents/domain.md`** (renamed via `git mv`): keep "read `GLOSSARY.md` and relevant `docs/adr/` before exploring; proceed silently if missing; create lazily via `/domain-modeling`", "use the glossary's vocabulary", and "flag ADR conflicts". Drop `GLOSSARY-MAP.md`, both file trees, the context-scoped ADR paths, and the references to `/grill-with-docs` and `/improve-codebase-architecture`, which don't exist here.
- **AGENTS.md:** merge "Save decisions", "Domain docs", and "Glossary" into one short section that says to use the `domain-modeling` skill for ADRs and glossary terms and imports `@docs/agents/domain.md`. Drop the backticks around the path so the import resolves. Remove the `@docs/adr/0000-adr-format.md` and `@GLOSSARY-FORMAT.md` imports.

## Left to the builder

Exact wording, kept brief (YAGNI/KISS).
