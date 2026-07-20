# Keel v0.1.2

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
| `agents/verifier.md` | Adversarial diff check — the full 11-shortcut catalogue. |
| `bin/check-budget.sh` | Counts assembled standing context; warns at 250 lines, fails at 300. |

## The two walls

Keel's protections live in two different layers, and it matters which one you
are trusting:

**Permission rules** (`settings.json`) protect the *interactive* door — a
developer at a terminal, where allows suppress prompt fatigue and denies are
live. In headless sandbox runs with permission-skipping enabled, deny rules
were observed NOT to block (probe: target-keel-05), so treat them as
developer-session guardrails, not sandbox security.

**The container boundary** protects the *sandboxed* door — a read-only or
scoped repo mount, unmounted scratch that dies at destroy, allowlist-only
network. This is the wall that actually held in every probe. If a control must
hold against an agent, put it in the mount and the network, not the config.

## Install

Copy into the target repo. Two files must sit at Claude Code's standard
discovery paths; the rest stay under the keel directory:

- `settings.json` → `.claude/settings.json`
- `agents/verifier.md` → `.claude/agents/verifier.md`
- `CONVENTIONS.md` → `.claude/keel/CONVENTIONS.md`
- `hooks/require-green.sh` → `.claude/keel/hooks/require-green.sh` (executable)
- `bin/check-budget.sh` → `.claude/keel/bin/check-budget.sh` (executable)

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
measured task completion falls off sharply. `bin/check-budget.sh` enforces it.

## Versioning

- **MAJOR** — the target's local layer must change.
- **MINOR** — drop-in.
- **PATCH** — wording or additive rules.

State the Keel version in the target's `CLAUDE.md` so a session shows what it
is running.

## Changes

- **v0.1.2** — verifier carries the full 11-shortcut catalogue (sourced:
  moonrunnerkc/swarm-orchestrator, mined from 327 real agent PRs; the source's
  own precision data says these are tips, not proof — the mechanical gate and
  the human stay the deciders). Absolute-path deny patterns corrected to `//**`
  (leading `/` is project-root-relative in permission rules). "Two walls"
  section added after probe target-keel-05 showed deny rules do not bind in
  permission-skipping sandbox runs. `bin/check-budget.sh` added — the 300-line
  budget is now checked, not remembered.
- **v0.1.1** — durability rule (the diff is the deliverable); gate audit log.
- **v0.1** — initial: conventions, permissions, stop gate, thin verifier.

## Verified so far

- Stop gate: all three production branches observed — refuse on red with one
  retry then loud release (target-keel-02), pass on green (target-keel-04),
  loud nag when unconfigured (target-keel-05). Every firing is in
  `keel-gate.log`.
- Full pipeline: real bug fixed under the rules, cause not tests, diff in the
  working tree (target-keel-01, -04).
- Tier routing via task-spec env reaches the gateway aliases; the result
  record self-reports the model (target-keel-03, -05).
- Container boundary held in every probe; see "The two walls" for what the
  permission config does and does not do.

## Known open

- Verifier invocation: the checklist is complete, but no run has yet shown the
  verifier being invoked. Needs a task that requires it and an
  invocation-evidence channel.
- No installer. Install and upgrade are manual copies; write the installer at
  the second target or the third upgrade, whichever comes first.
- No drift detection. A direct edit to a managed file fails silently today.
