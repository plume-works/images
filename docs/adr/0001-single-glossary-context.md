# One glossary for the whole repo

The repo builds a small family of related container images that share one
vocabulary, so it is a single context: one `GLOSSARY.md` at the repo root, with
its format in `GLOSSARY-FORMAT.md`. We dropped the upstream multi-context
layout (`GLOSSARY-MAP.md` plus a glossary per context) as YAGNI; bring it back
only if images start needing terms that conflict with each other.
