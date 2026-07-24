# Session context

What an agent needs to know to work on waterline, that is not in the other
docs. `architecture.md` says what the system IS; `failure-log.md` says what
went wrong; `deferred.md` says what we chose not to build. This file says how
we work and where we are right now.

Read this at the start of a session, together with `architecture.md`,
`failure-log.md` and `deferred.md`. Those three are canonical over anything
remembered. So is this one.

---

## Working protocol

**Deliberate before building.** Propose, discuss, then build on explicit
instruction. Not the reverse.

**Command blocks.** One at a time when debugging. Label every block
`-- on MAC --`, `-- on RUNNER --`, or `-- on CONTROLLER --`. Labels must be
ASCII-clean: no apostrophes, no parentheses. This zsh does not have
`interactive_comments`, so a pasted `#` errors as a command, and an apostrophe
in a label once opened an unterminated string that swallowed a whole block
into a `quote>` prompt (failure-log #11).

**Never infer a filesystem location.** Use a path confirmed in-session, or open
the block with a step that fails loudly. `mkdir -p` on a wrong path creates the
wrong tree instead of failing, and the mistake surfaces many exchanges later
(failure-log #10). Confirmed paths: `~/projects/waterline`,
`~/projects/target-flaskapp`, `~/projects/trip-concierge` on the Mac;
`/opt/waterline/` and `/opt/waterline-repo/` on the runner.

**Author in repo, deploy to boxes, never write on a box.** This includes task
specs. `/opt/waterline/tasks/` is a deployment target, not an authoring
surface. The sequence is: write on the Mac, commit, push, pull on the box, copy
into place, verify it landed.

**Prefer whole-file rewrites to `sed`** for anything non-trivial.

**Say when you are inferring.** Inference is allowed; unmarked inference is
not.

**Never claim something is verified without naming the artifact that proves
it.** And: verifying an outcome is not verifying a mechanism. When a control is
layered, a passing probe identifies only that SOME layer held. Name the layer,
or the claim is unearned. No layer item is "closed" unless the artifact is in
the repo where it can be checked independently.

## Spend posture

Roughly $10 burned across the build to date, some of it on avoidable errors.

- The subscription CANNOT be used for sandbox runs — headless container, no
  OAuth session, and handing a personal long-lived credential to untrusted
  agent code would break the key model.
- The subscription SHOULD be used for Door-1 interactive verification on the
  Mac. It is free, and several findings (the `Write(//**)` isolation, the
  trust-prompt behaviour) came from free tests that a paid run could not have
  produced better.
- Probes are seconds-long, single-question, cheap tier, capped at $0.50.
- Always name `ANTHROPIC_MODEL` in the task spec, even on a trivial probe. An
  empty `env` means no tier is requested and the CLI picks its own model —
  target-tc-02 cost $0.21 to reply with one word.

## Version state (24 Jul 2026)

| Component | Version | Notes |
|---|---|---|
| Keel | v0.1.6 | `Edit(//**)` in, `Write(//**)` out. README header still says v0.1.4 — drift, fix at next paper touch |
| sandbox-run.sh | v0.9 | trust preflight, `settings_loaded` in result record |
| sandbox-base | v2 | trust baked; default in v0.9 is still `:v1`, so `:v2` must be named in the task spec |
| Claude Code (sandbox) | 2.1.210 | pinned |
| Claude Code (Mac) | 2.1.215 | intentional skew |
| uv / pnpm (image) | 0.11.31 / 11.15.1 | asserted at build, not printed |

## Where L4 stands (24 Jul)

**The question.** An agent in an unfamiliar repo spends most of its budget
learning the repo rather than doing the task, drags that learning along as
ballast it re-pays every turn, and forgets all of it at session end.

**The sequence, deliberately in this order.** One ordinary task on one
unprepared real repo → autopsy (which files were opened vs which mattered, what
was re-derived, turns, test re-runs) → fix the single biggest waste → re-run the
same task → the delta IS the discovered metric. No metrics invented up front.

**The target.** target-tripconcierge. Autopsy task: write direct unit tests for
the seven `make_*_task` builders in `agents/.../tasks.py`, which are currently
only transitively covered. Gate is `agents` + `mcp_server` pytest (151 tests,
about 4s). Backend suite is out of scope — it hard-requires a real Postgres,
which the sandbox cannot reach. Web suite out of the gate for pnpm friction.

**Status.** The baseline has not been run honestly yet. target-tc-01 is VOID
(it measured a harness whose settings were never loaded, and exhausted its
budget). tc-02 proved the trust fix. tc-03 probed the deny rules.

**Blocking gap.** The harness harvests a SUMMARY of each run — twenty
fields, no transcript. The autopsy needs turn-level data: which files were
opened, in what order, what was re-derived. Running the baseline against the
current harvest would produce a result that cannot be autopsied, which is
exactly how tc-01 was wasted. Proposed fix before the baseline:
`sandbox-run.sh` v0.8 capturing `claude -p --output-format stream-json`.

**The half we have not scoped.** The original L4 has two halves and only one is
planned. The second is test economics: record/replay cassettes for the app's
own LLM calls, a gateway test tier pointed at a local model, exit gate "the
full test suite runs at about $0". Also unscoped from the original: the setup
convergence path (`ensure-dev.sh`, `preflight.sh`, seeded users, dev-login,
unified logs) with its gate "a cold sandbox reaches green tests via the setup
script alone, no human touch". That partly conflicts with the 22 Jul decision
to bake deps into the image, which was made to keep the exploration number
clean. Decide whether it is deferred or dropped rather than letting it lapse.

## Open items, as of 24 Jul

**Verified.** Keel's `settings.json` loads in a sandbox (tc-02,
`settings_loaded: true`, zero trust warnings in stderr). No edit reached the
repo in tc-03 (`changed_files: 0`, harness-computed).

**Unverified.** Whether Keel's deny rules actually bite. tc-03's
`permission_denials` came back empty while the agent's own summary said the
Edit was refused. The agent's narration is not a harness artifact, and the run
produced nothing that could distinguish a real refusal from the agent reading
`.claude/settings.json` and concluding. That is a fake-done of exactly the shape
`verifier.md` catalogues.

**Inferred, not verified.** That the Stop hook registers from Keel's
`settings.json`. Established by elimination: the image contains no other hook
declaration, no user-level settings, and no `/home/agent/.claude` directory. The
live hypothesis is that the trust gate is scoped to the `permissions` block only
— the warning counts "10 permissions.allow entries", not the whole file — so
`hooks` loaded from the untrusted file all along. If true, the gate travelled
with the repo in all seven runs. This cannot be closed on Door 1: the
interactive trust prompt offers only "trust" or "exit", so there is no
untrusted-but-running state to observe. Closing it needs a deliberately
untrusted sandbox run.

**Never run.** The original L3 exit gate was a removal diagnostic — take out any
harness file and the predicted degradation appears. That is a stronger standard
than "the mechanism works": it tests that every file is load-bearing. It has
never been executed against Keel.

## Owed at the next paper touch

- `Write(//**)` is an invalid form; `Edit(//**)` is what enforces. Both the
  finding and the startup warning that revealed it.
- The trust trade-off: baking trust means the sandbox honours whatever
  permissions a cloned repo declares, unquestioned. Fine for our own targets;
  a threat-model line when targets are not ours. Sharpened by the inference
  above — if hooks load without trust, then hook execution was never gated by
  trust in the first place, and a cloned repo's `settings.json` can register
  arbitrary shell commands on agent lifecycle events. The container boundary
  still contains it.
- The `verify` tier rejects the CLI's `effort` parameter (API 400,
  "This model does not support the effort parameter"). The tier is currently
  unusable from Claude Code, which matters because `agents/verifier.md` is
  specced to run on Haiku. The gateway has no fallback configured and
  `drop_params` is evidently off — both defensible, since silent parameter
  dropping is the same silent-success shape the failure log keeps catching.
- `settings_loaded` semantics: it is computed by grepping stderr for the trust
  warning, so it means "no warning found", not "settings confirmed loaded". On
  a fast failed run with empty stderr it reports true, which is not the same
  claim.
- Keel README version drift (header v0.1.4, settings.json v0.1.6).
- The transcript-capture gap.
- `num_turns` is unreliable on long runs (reported 1 for a 20-minute run) but
  correct on short ones (3 on tc-03). Not universally broken.

## Divergences from the original layer-stack plan

Recorded so they are deliberate rather than forgotten.

| Original | Actual | Why |
|---|---|---|
| Hetzner | Netcup | Forced — missed invoice |
| Nix flake image | hand-written Dockerfile | Drifted. Nix's structural purpose at L7 was "one image, two consumers, drift impossible by construction". With a Dockerfile that becomes discipline instead, and the corepack incident is exactly the failure Nix was chosen to prevent. Asserted pins are the current stand-in; L7 will need a real mechanism |
| Harness = 7 files on Trip Concierge, root `AGENTS.md` | Keel = 5 files, versioned base + thin local layer, `CLAUDE.md` | Evolved. The base/local split and the promotion test are better than the original single-repo shape |

Still holding from the original: the gateway swap as a base-URL change; the L9
second tenant (a boring CRUD app with zero LLM calls, to prove the substrate is
not Trip-Concierge-shaped).

## Model and runtime swap

Swapping the model behind a tier is cheap, and is what L2 exists for. Sandboxes
hold a virtual key and an alias, never a provider, so pointing `execute` at a
different model is a controller config change.

Swapping the agent RUNTIME is not cheap. Keel assumes Claude Code specifically:
the `settings.json` schema, the Stop hook contract, the `permission_denials`
field, the `.claude/` discovery paths. A different agent CLI is an L3 question,
not an L2 one, and would need an abstraction Keel does not have. The
`effort`-parameter failure is a preview of what breaks when the model behind an
alias changes.
