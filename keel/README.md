# Keel v0.1

The base layer of an agentic engineering harness. Versioned, shipped into a
target repo, and not edited there.

Keel is deliberately small. Everything in it is a mechanism that holds across
repositories; anything true of only one codebase belongs in that repo's own
CLAUDE.md, settings.local.json, or .mcp.json.

## What ships

| File | Does |
|---|---|
| `CONVENTIONS.md` | Standing rules. Imported by the target's CLAUDE.md. |
| `settings.json` | Tool permissions, secret denial, hook registration. |
| `hooks/require-green.sh` | Stop gate — refuses to finish on a red suite. |
| `agents/verifier.md` | Adversarial check of a diff against the spec. |

## Install

Copy into `.claude/keel/` in the target repo. Add to the target's `CLAUDE.md`:

```
@.claude/keel/CONVENTIONS.md

## This repo
<repo-specific facts, commands, and layout>
```

Set `KEEL_TEST_CMD` in `.claude/settings.local.json`. Without it the
verification gate is off and will say so on every turn.

## Editing

Files here are managed. A direct edit is lost on the next upgrade. Repo-specific
behaviour goes in the local layer, which merges with rather than replaces this
one.

## The promotion test

A convention from a client repo joins this base layer only if all three hold:

1. It is true on **two or more** repos, not one.
2. It is a **mechanism or convention**, not a fact about a codebase.
3. It **displaces** something already here.

Rule three is the one that keeps this file short. Additions are cheap and
compound; the budget is the whole assembled context, and past roughly 300 lines
measured task completion falls off sharply.

## Versioning

- **MAJOR** — the target's local layer must change.
- **MINOR** — drop-in.
- **PATCH** — wording.

State the Keel version in the target's `CLAUDE.md` so a session shows what it
is running.

## Known open in v0.1

- `Write(/**)` / `Edit(/**)` deny semantics are unverified against a live repo.
- Subagent discovery under a nested `.claude/keel/agents/` is unconfirmed; the
  verifier may need to sit at `.claude/agents/`.
- The verifier's checklist is four items. The known catalogue is eleven.
- No installer. First install is a manual copy; write the installer at the
  second target.
- No drift detection. A direct edit to a managed file fails silently today.
