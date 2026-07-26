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

**Keel is source here, installed there.** The sandbox clones the target repo, so
the `.claude/settings.json` an agent actually reads comes from the target, not
from `keel/`. A Keel change is not live until it is installed into the target
repo and pushed. Every Keel version bump is a paired commit. Nearly cost a run
on 26 Jul.

**Confirmed paths, additions.** Deployed runner script is
`/opt/waterline/sandbox-run.sh` — not under a `bin/` subdirectory.
`/opt/waterline-repo/bin/` is the deployment source. Each run's cloned target
survives at `/opt/waterline/sandboxes/<task-id>/repo/`, since destroy removes
the container but not the workdir, and the workdir is cleared only at the start
of the next run of that same task id.

**File mtime is not a liveness signal.** The CLI's stdout redirect to
`claude-stream.jsonl` is buffered, so its mtime lags actual model calls by
minutes. Use `gateway-spend-timeline.jsonl` or `docker ps` instead.

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
| Keel | v0.2 | `Edit(//**)` removed. README header now v0.2 — drift cleared |
| sandbox-run.sh | v0.11 | ledger kill poller, gateway spend audit, verified revocation |
| sandbox-base | v2 | trust baked; default in v0.11 is still `:v1`, so `:v2` must be named in the task spec |
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

## Where L4 stands (26 July)

**target-tc-05 COMPLETED.** First completed run of the L4 effort.
`status: completed`, `exit_code: 0`, 2493s of 5400, `spend_usd` 5.371443,
`changed_files` 1, `base_sha` 4895eb8, `settings_loaded: true`,
`key_revoked: true`, `killed_by_poller: false`.

Both suites green: agents 83 passed 0 failed, mcp_server 99 passed 0 failed.
Gate fired once and passed: `2026-07-26T07:37:37Z branch=green result=pass
test_exit=0`.

Prior runs for contrast. tc-01 VOID (settings never loaded, budget exhausted).
tc-04 failed on a phantom 429 at 1063s having finished the write phase — 506
diff lines, 29 test functions — but never verifying.

## Open items, as of 24 Jul

**Verified.** Keel's `settings.json` loads in a sandbox (tc-02,
`settings_loaded: true`, zero trust warnings in stderr). No edit reached the
repo in tc-03 (`changed_files: 0`, harness-computed).

**Keel's deny rules bite.** ARTIFACT: tc-04 `claude-stream.jsonl`, four
occurrences of "denied by your permission settings". The image declares no
`Edit` rule, and only `Edit(path)` forms are matched by file permission checks,
so Keel's `settings.json` is the only possible source.

**Keel's deny rules do not hold.** Same artifact: `Write` denied, then
`cat > <same path> << ENDOFFILE` succeeded; later `Edit` denied, then a
`python3 -c` rewrite of the same file succeeded. Two denials, two immediate
Bash route-arounds to the identical path, same turn each time. The rule blocks
the Edit and Write tools and nothing else.

**`Edit(//**)` was also unworkable, not merely porous.** The path it denied was
`/workspace/repo/agents/tests/test_tasks.py` — the agent's own assigned work.
`//**` matches every absolute path including the target repo, and it cannot be
narrowed, because deny beats allow. Keel's own file already assumes that
precedence: `Read(*)` in allow alongside `Read(./.env)` in deny only makes
sense if deny wins.

**The Stop hook registers from Keel's `settings.json`.** Was inferred by
elimination since 22 Jul. ARTIFACT: `keel-gate.log` exists and contains a
firing. The hook is declared only in Keel's `settings.json`, so that is where
it registered.

**Done means verified.** ARTIFACT: the same gate line. `require-green.sh` ran
`KEEL_TEST_CMD` itself and saw exit 0 — the agent's own claim was not the
gate.

**Unverified.** Whether Keel's deny rules actually bite. tc-03's
`permission_denials` came back empty while the agent's own summary said the
Edit was refused. The agent's narration is not a harness artifact, and the run
produced nothing that could distinguish a real refusal from the agent reading
`.claude/settings.json` and concluding. That is a fake-done of exactly the shape
`verifier.md` catalogues.

**The secret and destructive-Bash denies have never been probed.** Eight
entries survive in v0.2. Zero of them fired across tc-04's 24 turns or tc-05's
run. By the rule from failure-log #12, a deny is not deployed until a probe has
watched it refuse — so these are retained intentions, not demonstrated
controls.

**tc-04's phantom 5.0 is unexplained.** The rejection read "Current cost: 5.0,
Max budget: 5.0" while the ledger recorded 2.4483788 and the Console delta was
$2.45. Three hypotheses were falsified: a shared budget object (the mint sets
`max_budget` on the key itself), key reuse across attempts (the attempts were a
day apart and keys expire in 1h), and double counting (`/spend/logs` matched
the ledger exactly). tc-05 never tripped enforcement, so it produced no data.
`gateway-key-info.json` for tc-05 is unremarkable — spend 5.371443, max_budget
40.0, `user_id` null, `team_id` null. The capture works; there was no anomaly
to capture.

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
- (added below on 26 July)
- `docs/change-log.md` needs rows for sandbox-run.sh v0.11, task target-tc-05,
  and the target-tripconcierge Keel v0.2 install.
- `docs/failure-log.md` #12's fix column claims "sandbox Bash redirect to the
  denied path also denied and recorded in permission_denials". Both halves are
  contradicted — #13 attributed those refusals to the image, and tc-04 shows a
  Bash redirect succeeding with `permission_denials` empty.
- New failure-log entry: `permission_denials` returns empty while denials are
  present in the stream. Reproduced on tc-04. Eighth instance of the
  silent-success shape.
- `num_turns` reported 1 for a 2493-second, 46-plus-call run. Reproduced.
  Count turns from the stream.
- Keel's two-walls section still describes speed bumps as walls. After v0.2 the
  deny list contains no walls at all: three unprobed Read intentions and five
  Bash speed bumps that any agent can route around exactly as tc-04 did. The
  walls are the container on Door 2 and the image's `managed-settings.json`,
  which loads without trust and cannot be shaped by a cloned repo.
- Door 1 has no file-write boundary at all now, and no container. That is a
  threat-model line to state, not a gap to paper over.


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

## Cost measurement (26 July)

**The gateway ledger is truth. `model_usage.costUSD` is not.** Confirmed on two
runs against the Console.

| Run | model_usage sum | ledger | Console delta |
|---|---|---|---|
| tc-04 | $2.2243 | $2.4484 | $2.45 |
| tc-05 | $2.8216 | $5.3714 | $5.37 |

The CLI applies a fallback price table to aliases it cannot resolve — verified
by reconstruction on both runs at $5/M input, $25/M output, 0.1x cache read,
1.25x cache write. Its error grows with cache-creation volume: 1.10x wrong on
tc-04 with 76,645 creation tokens, 1.90x wrong on tc-05 with 179,552. Never
quote `model_usage.costUSD` as spend.

**Per-tier attribution through the alias does not work.** `/spend/logs` records
`execute` at 0.00 and puts the money under the resolved model name. An L8
economics problem, now evidenced.

**The pass-through bypass persists.** tc-05 spent $0.536 on
`claude-opus-4-8[1m]`, roughly 10% of the run, on a model the task never asked
for.

**Burn rate within a run is not constant and not monotonic.** From tc-05's
timeline: about $0.40/min for the first 96 seconds (cache creation at 1.25x),
settling to $0.118/min, climbing to $0.134 and then $0.177 through the
verify-and-fix phase, then collapsing to $0.070/min after the gate passed.

## The autopsy (26 July)

Two wastes, both named from artifacts, neither invented in advance.

**Waste 1 — redundant re-verification, about 31% of the run.** After both
suites were green and the gate had passed, the agent re-ran the suites twice
more. Its closing messages: "The second agents-suite run also completed with
exit code 0", then "All three independent runs confirmed. Nothing further to
act on."

Arithmetic, from three artifacts:

- `keel-gate.log` gives the gate time: 07:37:37Z
- `gateway-spend-timeline.jsonl` at 07:37:47 reads 3.683295949999999
- the result record gives final `spend_usd` 5.371443199999998
- 5.371443 − 3.683296 = **1.688147**, which is **31.4%** of the run

Candidate fix: a CONVENTIONS.md line stating that the gate performs
verification, so re-running the suite to satisfy oneself is spend without
signal.

**Waste 2 — dependency knowledge derived by trial and error.** The agent
discovered that CrewAI 1.14.5 stores a truthy `NOT_SPECIFIED` sentinel in
`Task.context` when `context=` is omitted, so the obvious `assert not
task.context` fails. It documented this in a code comment. This is a fact about
a pinned dependency, absent from the bare CLAUDE.md, and rediscovering it costs
real turns.

Candidate fix: it belongs in the map — which makes it a concrete first entry
for the mapped arm rather than a guess at what a map should contain.
