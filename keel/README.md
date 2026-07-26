# Keel v0.2

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

## The two walls (corrected 22 Jul)

Keel's protections live in layers that guard different doors and fail
differently. Each is marked with what actually proves it.

**Keel's permission rules** (`settings.json`) — **live on Door 1, UNVERIFIED
on Door 2.** An interactive session denied an absolute-path Write outright with
no prompt (Door 1 test, 20 Jul). In sandbox runs, Claude Code has refused to
load this file every time: *"Ignoring 10 permissions.allow entries from
.claude/settings.json: this workspace has not been trusted"* appears in the
stderr of all seven runs to date. Until the workspace-trust fix ships, assume
this file does nothing in headless runs.

**The image's managed settings** (`/etc/claude-code/managed-settings.json`,
outside this repo, no trust required) — **VERIFIED on Door 2.** This is what
refused the Write and the Bash redirect in probe target-keel-06; that result
was originally and wrongly credited to the file above.

**The container boundary** — scoped mounts, unmounted scratch that dies at
destroy, allowlist-only network — **VERIFIED.** Held in every run, including
all seven in which the repo-level config layer was silently absent. That is the
argument for layered walls: they fail independently, and one of them was
failing the whole time.

The caution, now earned twice: **an invalid pattern is silently ignored, and an
untrusted settings file is silently ignored.** v0.1 shipped `Write(/**)` — one
slash short of `//**` — with no protection and no warning for five runs; the
corrected pattern then sat in a file nobody was reading. Validate a rule by
watching it refuse, and confirm which layer refused. A deny you have only read
is a deny you do not have.

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

Each file's header records the Keel version at which that file last changed;
this README states the current release. A file whose header says an older
version is unchanged since then, not stale.

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

- **v0.1.4** — documentation correction, no behaviour change. Two-walls section
  and the verified list re-marked after discovering that `settings.json` has
  never been loaded in a sandbox run (workspace trust); headless deny
  verification reattributed to the image's managed settings; tier-routing
  control marked partial. Nothing here was demoted for being wrong in
  substance — only for having been credited to the wrong layer.
- **v0.1.3** — two-walls section rewritten after probe target-keel-06: deny
  rules verified to bind on both doors, including Bash-redirect inspection;
  the true run-05 failure was an invalid pattern silently ignored, not a
  flag bypass. Header convention documented (headers = last-changed version).
- **v0.1.2** — verifier carries the full 11-shortcut catalogue (sourced:
  moonrunnerkc/swarm-orchestrator, 327 mined agent PRs). Absolute-path deny
  patterns corrected to `//**`. `bin/check-budget.sh` added.
- **v0.1.1** — durability rule (the diff is the deliverable); gate audit log.
- **v0.1** — initial: conventions, permissions, stop gate, thin verifier.

## Verified so far

- Deny rules (Door 1 only): absolute-path Write refused interactively with no
  prompt, 20 Jul. The headless refusals in target-keel-06 came from the image's
  managed settings, not from this file — see "The two walls".
- Stop gate behaviour: all three production branches observed — refuse on red
  with one retry then loud release (target-keel-02), pass on green
  (target-keel-04), loud nag when unconfigured (target-keel-05). Every firing
  is in `keel-gate.log`. The behaviour is verified; how the hook was registered
  is not, since the settings file declaring it was never loaded.
- Full pipeline: real bug fixed under the rules, cause not tests, diff in the
  working tree (target-keel-01, -04).
- Tier routing reaches the gateway aliases and the result record self-reports
  the model (target-keel-05, -06 — single `execute` key each). Control is
  partial: gateway pass-through entries let CLI-issued model strings bypass the
  tier, observed in target-tc-01.
- Container boundary held in every probe, including while the config wall was
  silently absent.

## Known open

- **Workspace trust (blocking).** Repo-level settings are ignored unless the
  workspace is trusted. The fix is environment state — `hasTrustDialogAccepted`
  for the workspace path in the agent's `.claude.json`, baked into the image —
  not something this repo can carry. Until it ships, of the five files here
  only `CONVENTIONS.md` (imported by CLAUDE.md) and `bin/check-budget.sh` are
  demonstrably doing anything in a sandbox.
- Verifier invocation: the checklist is complete, but no run has yet shown the
  verifier being invoked. Needs a task that requires it and an
  invocation-evidence channel.
- No installer. Install and upgrade are manual copies; write the installer at
  the second target or the next upgrade, whichever comes first (three manual
  copies done — the case is made).
- No drift detection. A direct edit to a managed file fails silently today.
