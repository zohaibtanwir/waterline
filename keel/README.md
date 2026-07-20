# Keel v0.1.1

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
| `hooks/require-green.sh` | Stop gate — refuses to finish on a red suite. Audits to the out mount. |
| `agents/verifier.md` | Adversarial check of a diff against the spec. |

## Install

Copy into the target repo. Two files must sit at Claude Code's standard
discovery paths; two stay under the keel directory:

- `settings.json` → `.claude/settings.json`
- `agents/verifier.md` → `.claude/agents/verifier.md`
- `CONVENTIONS.md` → `.claude/keel/CONVENTIONS.md`
- `hooks/require-green.sh` → `.claude/keel/hooks/require-green.sh` (executable)

Add to the target's `CLAUDE.md`:

```
@.claude/keel/CONVENTIONS.md

## This repo
<repo-specific facts, commands, and layout>
```

Set `KEEL_TEST_CMD` in `.claude/settings.local.json` (human sessions) or the
task spec's `env` block (sandboxed runs). Without it the verification gate is
off and will say so on every turn.

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
- **PATCH** — wording or additive rules.

State the Keel version in the target's `CLAUDE.md` so a session shows what it
is running.

## Changes

- **v0.1.1** — durability rule (the diff is the deliverable; environment-only
  fixes do not count as done — from run target-keel-03, where a green run
  produced an empty diff); gate writes an audit line per firing to
  `/workspace/out/keel-gate.log` when the out mount exists (from run
  target-keel-02, where gate evidence existed only in the agent's narrative).
- **v0.1** — initial: conventions, permissions, stop gate, thin verifier.

## Verified so far

- Stop gate fires, refuses, retries once, releases loudly (run target-keel-02).
- Full pipeline: real bug fixed under the rules, cause not tests (run
  target-keel-01).
- Tier routing via task-spec env reaches the gateway aliases (run
  target-keel-03).

## Known open

- `Write(/**)` / `Edit(/**)` deny semantics remain unverified — run 03's
  out-of-repo file was created via Bash, which permission rules on Write do
  not cover; a dedicated probe is queued.
- The verifier's checklist is four items; the known catalogue is eleven. No
  evidence yet that the verifier is invoked at all.
- No installer. Install and upgrade are manual copies; write the installer at
  the second target or the second upgrade, whichever comes first.
- No drift detection. A direct edit to a managed file fails silently today.
