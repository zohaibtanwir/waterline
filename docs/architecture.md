# Waterline — architecture

Living document. Updated at the close of each layer. Current as of **L4 first
result (27 Jul 2026)**.

> **22 Jul reconciliation.** A trust-dialog defect discovered during the first
> L4 run showed that Keel's `settings.json` was never applied in ANY sandbox
> run. Claims in the L3 section that rested on it have been re-marked against
> the artifacts that actually prove them. See failure-log #13.

> **27 Jul update.** The trust defect is fixed and the claims it invalidated are
> now settled — some confirmed, some overturned. Keel's `settings.json` DOES
> load and its Stop hook DOES register (target-tc-05's `keel-gate.log`). Its
> deny rules DO bite and DO NOT hold (target-tc-04's stream). L4's first half
> has a measured result; L4's stated thesis remains untested. Every claim below
> carries its evidence or is explicitly marked unverified.

> Maintenance rule: this file is a close-out deliverable. At each layer's close,
> update the diagram, the component status table, and the file trees to match
> what was actually built — then commit. It documents *state*, so it must never
> lag the boxes.

## Layer status

| Layer | Scope | Status |
|-------|-------|--------|
| L0 | Infrastructure — two hardened boxes, tailnet-only | ✅ built |
| L1 | Containment & execution — sandboxes, proxy, lifecycle | ✅ built |
| L2 | Gateway & routing — LiteLLM, virtual keys, Langfuse | ✅ built |
| L3 | Harness — Keel on a real repo; tier-routing wired; probe-verified | ✅ built |
| L4 | Codebase legibility + test economics | ◐ in progress — first half has a result; thesis untested |
| L5 | Knowledge & memory — skills marketplace, learning capture | ☐ planned |
| L6 | Dispatcher & channels — Telegram/Slack; runner fleet bootstrap | ☐ planned |
| L7 | Gates & review — CI, review agents, artifact gates | ☐ planned |
| L8 | Observability & economics — dashboards, model-name-in-traces gap | ☐ planned |
| L9 | Validation — real task runs, failure log at scale | ☐ planned |

Note: the loop runner (outer Plan→Act→Verify iteration) is deliberately
assigned to NO layer. Its adoption and placement require their own debate;
design forks are held warm in docs/deferred.md.

## System diagram

```
                          Your Mac
                     Tailscale SSH only
                            |
                tailnet (100.x) — no public ports
                |                                |
                v                                v
  +=================================+   +==================================+
  |  waterline-control              |   |  waterline-runner-1              |
  |  100.98.245.52 · durable · 16GB |   |  100.109.125.122 · disposable    |
  |                                 |   |                                  |
  |  [LIVE] tinyproxy :8888         |   |  [LIVE] sandbox-run.sh v0.12.1   |
  |    allowlist (github/pypi/npm)  |   |    mint→inject→exec→harvest→      |
  |    api.anthropic.com REMOVED    |   |    destroy(+verified revoke)     |
  |                                 |   |    turn-stream capture;          |
  |  [LIVE] LiteLLM gateway :4000   |   |    ledger kill poller;           |
  |    v1.89.0 · real Anthropic key |   |    gateway spend audit           |
  |    tier aliases plan/exec/verify|   |                                  |
  |    (wired at L3: task-spec      |   |  [LIVE] sandbox-base:v2 image    |
  |     ANTHROPIC_MODEL=alias)      |   |    Claude Code 2.1.210 pinned    |
  |    mints per-task virtual keys  |   |    uv 0.11.31 · pnpm 11.15.1     |
  |                                 |   |    workspace trust baked         |
  |  [LIVE] Langfuse :3000 (6 svc)  |   |                                  |
  |    traces + per-task cost       |   |  sandbox-net 172.30.0.0/24       |
  |                                 |   |    iptables → controller ONLY    |
  |  agent code NEVER runs here     |   |   +--------------------------+   |
  +==========|=============^========+   |   | sbx-<task> (per task)    |   |
             ^             |            |   | holds ONLY a virtual key |   |
             |             |            |   | Keel-governed (target)   |   |
   model calls (:4000)  admin: mint/revoke  | non-root · capped · dies |   |
   virtual key          via master key on   +--------------------------+   |
             |          runner HOST      +======|=================|=========+
             +---------------------+            |                 |
                                   |  git/pkg (:8888)   model (:4000)
                                   |  via proxy         via virtual key
                                   v                    |
                             allowlisted internet       |
                             github · pypi · npm        |
                                   +----- Anthropic API <+
                                     (only the gateway holds the
                                      real key; sandboxes never do)
```

Trust is one-way: the controller dispatches work **down** to runners; agent code
never flows **up**. Every model call is metered and traced. Sandbox egress has
exactly two controller-side paths — the proxy (git/packages, allowlisted) and the
gateway (model calls, virtual-key-authenticated). Direct sandbox→internet is
blocked by iptables.

## The key model (security invariant)

```
  real Anthropic key   →  CONTROLLER only            (can spend real money)
  LiteLLM master key   →  controller + runner HOST   (mints virtual keys;
                                                       cannot call Anthropic;
                                                       NEVER enters a sandbox)
  per-task virtual key →  SANDBOX only               (budget-capped per task
                                                       spec, revoked at destroy
                                                       — a dead ticket)
```

A fully compromised sandbox yields only a spent, budget-capped virtual key.

**Revocation is now verified, not assumed (v0.11).** The old teardown discarded
the delete response and forced its exit code to zero, so a failed revocation
printed the same success line as a good one and left a budget-capped key live
for its full hour. The harness now re-queries the key after deleting it and
records `key_revoked` from whether it still resolves.

## Budget layers — there are three, and they must nest

```
  Anthropic workspace monthly spend limit   $50   ← upstream of the gateway,
                                                    INVISIBLE to the harness
  LiteLLM virtual-key max_budget             20   ← caps.budget_usd
                                                    (the unreliable counter)
  Ledger kill poller                         15   ← caps.kill_usd
                                                    (the only one ever correct)
```

Each layer must be looser than the one inside it, or the least reliable counter
decides the outcome. This was learned twice. target-tc-04 was refused by the
gateway at "Current cost: 5.0, Max budget: 5.0" while the ledger recorded
2.4483788 and the Console delta was $2.45 — a number that appears in no record
(deferred: phantom 429). target-tc-06's first attempt died at 112 seconds on the
workspace limit, a layer that existed outside the harness and outside these docs
(failure-log #17). **Check workspace headroom before any run.**

`caps.budget_usd` is deliberately set looser than `caps.kill_usd` because it
feeds the counter that threw the phantom 5.0. The real cap is the poller, which
samples the ledger — the number that has matched the Anthropic Console on every
run where both were observed.

## Lifecycle: mint → inject → exec → harvest → destroy  (v0.12.1)

1. **preflight** — refuse to start (exit 3) on an image that does not mark
   `/workspace/repo` trusted. A run on an untrusted image is a run whose harness
   does nothing (failure-log #13).
2. **mint** — runner calls gateway /key/generate (master key) → per-task virtual
   key, budget-capped
3. **inject** — host clones repo (host holds git PAT), chowns to agent uid,
   mounts in: repo (ro|rw per task spec) + a separate out-mount for
   report/audit; task-spec `env` object injected as container environment
   (KEEL_TEST_CMD, ANTHROPIC_MODEL)
4. **poll** — background loop samples `/key/info` every 30s into
   `gateway-spend-timeline.jsonl` and tears the container down at
   `caps.kill_usd`
5. **exec** — `claude -p --output-format stream-json --verbose` as non-root;
   ANTHROPIC_BASE_URL→gateway, ANTHROPIC_API_KEY=virtual key; venv/caches on
   unmounted paths — they die with the container
6. **harvest** — host computes diff (excludes as safety net) + result record;
   derives the summary from the LAST `"type":"result"` line of the stream (never
   `tail -1`, which on a timeout kill grabs a mid-stream object that parses to
   nulls); counts turns, denials and gate firings FROM THE STREAM rather than
   from the agent's report; captures `/key/info` and `/spend/logs` to disk while
   the key still exists
7. **destroy** — container removed AND virtual key revoked, then re-queried to
   confirm

### The result record tells the truth (v0.12)

Four fields read as authoritative and were not (failure-log #14). All are now
derived from artifacts or renamed to what they measure:

| Field | Was | Now |
|---|---|---|
| turns | `num_turns` — reported 1 for a 2493s run | `turns_from_stream`, counted from assistant messages. `num_turns` retained alongside so the CLI bug stays visible |
| denials | `permission_denials` — `[]` while four sat in the stream | `denials_from_stream`, counted from the stream |
| settings | `settings_loaded` — meant "no warning found in stderr" | `trust_warning_absent` |
| cost | `model_usage.costUSD` — the CLI's fallback price table | `costUSD_cli_estimate`. The gateway ledger is authoritative |
| gate | absent — tc-05's gate fired twice and the record was silent | `gate_firings`, counted from `keel-gate.log` |

## L3 — the harness (as built, closed 20 Jul 2026; re-verified 26-27 Jul)

L3 answers the question the layers below cannot: is the work real? L0-L2
contain the agent and meter it; L3 governs it. The deliverable is **Keel** —
a versioned base layer of working rules and mechanical gates that installs
into any target repo.

### The two-layer model

```
            KEEL  (versioned base -- substrate IP, waterline/keel/)
            CONVENTIONS.md  settings.json  hooks/require-green.sh
            agents/verifier.md  bin/check-budget.sh        v0.3
                          |
                          |  install (manual; installer deferred, case made)
                          v
   +----------------- target repo ------------------------------+
   |  CLAUDE.md ("## This repo" facts) --imports-->             |
   |      .claude/keel/CONVENTIONS.md                           |
   |  .claude/settings.json         (managed, standard path)    |
   |  .claude/agents/verifier.md    (managed, standard path)    |
   |  .claude/keel/hooks/require-green.sh                       |
   |  .claude/settings.local.json   (theirs, gitignored)        |
   +------------------------------------------------------------+
        ^                                      ^
   Door 1: developer terminal            Door 2: sandbox task
   interactive; prompts + denies live    headless; container is the wall
```

Base is ours and versioned (MAJOR/MINOR/PATCH; file headers record the
version at which each file last changed). Local is theirs. The seam is an
import plus a merge — upgrades are file swaps, never re-derivation. Backflow
is governed by the promotion test (true on 2+ repos; mechanism not codebase
fact; displaces something).

**Keel is source here and installed there.** The sandbox clones the target repo,
so the `.claude/settings.json` an agent reads comes from the target, not from
`waterline/keel/`. A Keel change is not live until it has been installed into
the target and pushed. Every version bump is a paired commit in both repos.

### The walls (corrected 22 Jul, corrected again 27 Jul)

Protection is layered. What each layer is proven to do — and by which artifact:

- **The image's managed settings** (`/etc/claude-code/managed-settings.json`,
  baked read-only, requires no workspace trust) — **VERIFIED.** This is what
  refused the absolute-path Write and the Bash redirect in probe
  target-keel-06. Its deny list covers `.env`/secret reads, `rm -rf /*`,
  force-push, and curl-pipe-to-shell. It is enforced outside the workspace, so
  a cloned repo's own settings cannot shape it.
- **The container boundary** (ro/scoped mounts, unmounted scratch, allowlist
  network) — **VERIFIED.** Held in every run.
- **Keel's repo-level `settings.json`** — **LOADS (verified), BITES (verified),
  DOES NOT HOLD (verified).** Three separate claims, settled separately:
  - *Loads:* sandbox-base:v2 bakes `hasTrustDialogAccepted` for
    `/workspace/repo`. `trust_warning_absent` is true on tc-05 and tc-06 and no
    trust warning appears in stderr.
  - *Bites:* target-tc-04's stream contains four "denied by your permission
    settings" tool results. The image declares no `Edit` rule and only
    `Edit(path)` forms are matched by file permission checks, so Keel's file is
    the only possible source.
  - *Does not hold:* in that same stream, `Write` was denied and then
    `cat > <same path> << ENDOFFILE` succeeded; later `Edit` was denied and a
    `python3 -c` rewrite of the same file succeeded. Two denials, two immediate
    Bash route-arounds to the identical path, in the same turn each time. The
    rule blocks the Edit and Write tools and nothing else.

**`Edit(//**)` was removed at Keel v0.2, and porousness was not the only
reason.** The path it denied in tc-04 was
`/workspace/repo/agents/tests/test_tasks.py` — the agent's own assigned work.
`//**` matches every absolute path including the target repo, and it cannot be
narrowed, because deny beats allow. Keel's own file already assumes that
precedence: `Read(*)` in allow alongside `Read(./.env)` in deny only makes sense
if deny wins.

**What remains in the deny list is not a wall.** Three `Read` secret rules and
five `Bash` rules survive at v0.2. None has ever fired —
`denials_from_stream` is 0 on tc-05 and tc-06. By the rule from failure-log
#12, they are retained intentions, not demonstrated controls. The `Bash` rules
are porous by the same mechanism tc-04 demonstrated: an agent that answers a
blocked `Edit` with `python3` will answer a blocked `rm -rf` the same way.

**Door 1 now has no file-write boundary and no container.** That is a
threat-model line, not a gap to paper over (deferred: two-walls documentation).

The surviving caution from failure-log #12 stands and is now triply earned:
**an invalid pattern is silently ignored, an untrusted settings file is silently
ignored, and a valid rule can be routed around in the same turn.** A deny you
have only read is a deny you do not have.

### Done means verified

- The Stop gate (`require-green.sh`) refuses the agent's finish on a red
  suite (exit 2), allows one retry, then releases loudly as UNVERIFIED.
  All three branches were observed in production and every firing is audited
  to `/workspace/out/keel-gate.log`. **Behaviour verified; registration path NOW
  ALSO VERIFIED.** target-tc-05's `keel-gate.log` contains
  `2026-07-26T07:37:37Z branch=green result=pass test_exit=0`. The hook is
  declared only in Keel's `settings.json`, so that is where it registered from.
  This closes the 22 Jul open question: the gate travels with the repo.
- **The gate does the verifying, and that is now a documented rule.** Keel v0.3
  adds it to CONVENTIONS.md after target-tc-05 spent 31% of its budget re-running
  a suite the gate had already passed (failure-log #15).
- The diff is the deliverable: a fix that lives only in the disposable
  environment does not count (rule added in v0.1.1 after run 03 produced
  green tests with an empty diff).
- The verifier subagent carries the full 11-shortcut fake-done catalogue
  (sourced from a 327-PR mining study). Flags are tips; the gate and the
  human are the deciders. **Still no run has required it.**
- The assembled standing context (CLAUDE.md + imports) is budget-checked
  mechanically: soft 250 lines, hard 300 (bin/check-budget.sh).

### Tier routing

One line in the task spec — `"env": {"ANTHROPIC_MODEL": "execute"}` — reaches
the L2 gateway aliases. **VERIFIED, PARTIAL.** The alias resolves correctly:
target-tc-05's `/spend/logs` shows `execute` resolving to
`anthropic/claude-sonnet-4-6`.

**The control is not total, and the bypass now has numbers.** The gateway also
exposes pass-through entries mapping the literal model strings Claude Code
requests straight to real models — added at L2 so sandbox behaviour kept
working. Any call the CLI issues under its own model string bypasses the tier
and is served anyway. target-tc-05's per-request ledger:

| model | requests | spend |
|---|---|---|
| anthropic/claude-sonnet-4-6 | 103 | $4.8349482 |
| anthropic/claude-opus-4-8 | 7 | $0.5364950 |
| execute | 1 | $0.00 |

The three sum to `spend_usd` (5.3714432) exactly, so the Opus traffic is real
rather than a reporting artifact. Six percent of requests, ten percent of spend,
roughly 1.6x more expensive per request. **What issues those requests is
unknown.** Subagents are the obvious candidate — tc-05's init record listed
`Explore`, `Plan`, `general-purpose` and Keel's `verifier`, and its tool mix
included one `Agent` call — but this is not confirmed.

`ANTHROPIC_MODEL` steers; it does not constrain.

**Per-tier cost attribution through the alias does not work.** `/spend/logs`
records `execute` at $0.00 and puts the money under the resolved model name.
That is an L8 problem, now evidenced.

### Cost measurement — settled across three runs

**The gateway ledger is authoritative. `model_usage.costUSD` is not.**

| Run | model_usage sum | ledger `spend_usd` | Console delta |
|---|---|---|---|
| tc-04 | $2.2243 | $2.4484 | $2.45 |
| tc-05 | $2.8216 | $5.3714 | $5.37 |
| tc-06 (both attempts) | — | $0.932 + $2.430 | $3.36 |

The CLI applies a fallback price table to aliases it cannot resolve — verified
by reconstruction on two runs at $5/M input, $25/M output, 0.1x cache read,
1.25x cache write, applied IDENTICALLY to `execute` and to `claude-opus-4-8`,
which is the giveaway. Its error grows with cache-creation volume: 1.10x wrong
on tc-04 (76,645 creation tokens), 1.90x on tc-05 (179,552).

The ledger has matched the Anthropic Console on every run where both were
observed. **Never quote `costUSD_cli_estimate` as spend.**

### Evidence (runs 01-06, tc-01 to tc-06)

| Run | Question | Answer |
|---|---|---|
| 01 | Does a real bug get fixed under the rules? | Yes — cause not tests, 3 files, $0.99 (Opus) |
| 02 | Is the Stop gate wired? | Yes — rigged-to-fail task; refusal, retry, loud release |
| 03 | Does tier routing work? | Yes — and exposed the ephemeral-fix loophole (green, empty diff) |
| 04 | Does the durability rule close it? | Yes — same fix as Opus, in the tree, $0.78 (Sonnet) |
| 05 | Does the write-deny hold? | No — invalid pattern silently ignored; container held |
| 06 | Does the corrected deny hold? | Yes — but the refusal came from the IMAGE's managed settings, not Keel's (corrected 22 Jul) |
| tc-01 | L4 baseline on a real repo | VOID — budget exhausted at $2.22/1198s; measured a harness whose settings were never loaded |
| tc-02 | Does the trust fix work? | Yes — `settings_loaded: true`, zero trust warnings |
| tc-03 | Do Keel's denies bite in a sandbox? | Inconclusive at the time — `permission_denials` empty while the agent narrated a refusal. Settled later by tc-04's stream |
| tc-04 | L4 baseline, honest re-run | FAILED at 1063s on the phantom 429. Write phase complete (506 diff lines, 29 tests), never verified. Its stream settled the deny question |
| tc-05 | L4 baseline, completed | COMPLETED. 2493s, $5.371443, 30 tests, gate fired twice. The autopsy source |
| tc-06 (1st) | — | VOID at 112s — Anthropic workspace spend limit (failure-log #17) |
| tc-06 (2nd) | Does the autopsy fix work? | Yes. 1059s, $2.430470, 41 tests, gate fired once |

### Exit gates

Re-marked 22 Jul, updated 27 Jul.

1. **MET.** Keel installed in a real target; a genuine pre-existing bug fixed
   under its rules with the diff as deliverable (runs 01, 04).
2. **NOW MET, WITH THE SCOPE STATED HONESTLY.** The original wording — "every
   harness mechanism verified by direct probe on both doors, zero claims resting
   on inference" — was false when declared. Keel's repo-level settings are now
   verified in sandbox runs: they load (tc-05 `trust_warning_absent`), the hook
   registers from them (tc-05 `keel-gate.log`), and the deny rules bite (tc-04
   stream). What is NOT verified is the surviving eight deny entries, none of
   which has fired in any run. Those are named as unverified rather than
   claimed.
3. **PARTIALLY MET.** Tier routing reaches the gateway (verified); tier
   *control* is partial (pass-through bypass, now quantified) and the original
   economics remain withdrawn.
4. **MET.** Context budget mechanically enforced (`bin/check-budget.sh`,
   exercised on both targets).
5. **MET.** Paper trail current: change-log, failure-log (#10-17), deferred
   register, Keel changelog.

**Never run:** the original L3 exit gate was a removal diagnostic — take out any
harness file and the predicted degradation appears. That is a stronger standard
than "the mechanism works": it tests that every file is load-bearing. Keel v0.3's
CONVENTIONS.md line now has an A/B behind it, which is a partial instance of
exactly this diagnostic (deferred: removal diagnostic).

## L4 — codebase legibility and test economics

**Status: the first half has a measured result. The stated thesis is NOT tested.**

### The question, and the sequence

An agent in an unfamiliar repo spends most of its budget learning the repo
rather than doing the task, drags that learning along as ballast it re-pays
every turn, and forgets all of it at session end.

The sequence, deliberately in this order: one ordinary task on one unprepared
real repo → autopsy → fix the single biggest waste → re-run the same task → the
delta IS the discovered metric. No metrics invented up front.

### The target

target-tripconcierge, a real application rather than a 110-line toy. Autopsy
task: write direct unit tests for the seven `make_*_task` builders in
`agents/.../tasks.py`, which are only transitively covered. Gate is `agents` +
`mcp_server` pytest (151 tests, about 4s). The backend suite is out of scope —
it hard-requires a real Postgres the sandbox cannot reach, and the target's
CLAUDE.md carries a guardrail saying so. The web suite is out for pnpm friction.

The guardrail is scoped precisely, and the precision matters: it forbids
*running* the backend suite, not *reading* backend files. Reading while
orienting is genuine exploration cost and is the signal L4 measures; running an
unwinnable Postgres suite is environment noise. tc-04's stream confirms it held
— `backend` appears 44 times, all inside file contents the agent read, with zero
tool calls against any backend path.

### The baseline (target-tc-05)

COMPLETED. 2493s, $5.371443, `changed_files` 1, 30 tests written, both suites
green (agents 83 passed, mcp_server 99 passed), gate fired twice.

Two wastes named from artifacts, neither invented in advance:

**Waste 1 — redundant re-verification, about 31% of the run.** After both suites
were green and the gate had passed, the agent re-ran them twice more. Its
closing messages: *"The second agents-suite run also completed with exit code
0"*, then *"All three independent runs confirmed. Nothing further to act on."*
Arithmetic from three artifacts: `keel-gate.log` gives the first pass at
07:37:37Z; the spend timeline reads 3.683296 at 07:37:47; final `spend_usd` was
5.371443; the difference is $1.688147 of $5.371443.

**Waste 2 — dependency knowledge derived by trial and error.** The agent
discovered that CrewAI 1.14.5 stores a truthy `NOT_SPECIFIED` sentinel in
`Task.context` when `context=` is omitted, so `assert not task.context` fails on
a task that has no context. The string appears on 15 stream lines, six of them
tool results — real failures, not just narration. This is a fact about a pinned
dependency, absent from the target's bare CLAUDE.md.

### The fix and the A/B (target-tc-06)

Keel v0.3 added one paragraph to CONVENTIONS.md: run the test command once, in
the foreground; do not background it; do not re-run a passing suite for
confidence, because the Stop gate runs the same command itself.

Identical prompt, image, mount, env and target repo. tc-05 ran at base_sha
`4895eb8`, tc-06 at `21bdbd5`, and the only difference between those commits is
that paragraph plus a version line.

| | tc-05 | tc-06 |
|---|---|---|
| pytest invocations | 8 | 3 |
| gate_firings | 2 | 1 |
| spend_usd | $5.371443 | $2.430470 |
| duration_seconds | 2493 | 1059 |
| turns_from_stream | 70 | 50 |
| tests written | 30 | 41 |

**CLAIM — the fix works. EVIDENCE — a causal chain, each link with an artifact.**
The paragraph shipped at Keel v0.3 and reached the target at `21bdbd5`. Bash
tool calls mentioning pytest fell from 8 to 3, counted from the two streams;
three is close to the floor for this task, so tc-05 ran the suite five more
times than it needed to. `keel-gate.log` fell from two firings to one, meaning
the agent stopped when the gate told it it was done rather than continuing for a
further seventeen minutes. Ledger spend fell from $5.371443 to $2.430470, and
the Console credit delta of $3.36 across both tc-06 attempts matches
$0.932 + $2.430 exactly.

**Split at the gate.** tc-05 spent $1.69 after its gate passed; tc-06 spent
about $0.016 — the post-gate waste is gone. The pre-gate half also fell, $3.68
to $2.41, which the pytest count explains: the over-running was happening
throughout the run, not only after green.

**CLAIM NOT MADE — a general percentage improvement.** One run per arm. The
mechanism is established; the magnitude is a single observation. Whether eight
pytest invocations is typical of the unfixed arm or an unlucky run is unknown.

### What this does NOT establish

The fix measured here is **verification discipline, not repo legibility**. L4's
stated thesis — that an agent burns its budget learning an unfamiliar repo — is
untested. The mapped arm, putting discovered repo facts into the local layer and
re-running, has not been run. Waste 2 is its first earned entry: found by
watching a run rather than by guessing what a map should contain.

Standing caution: a map holding one fact that helps exactly this task would
produce a delta proving the mechanism works, not that maps generalise. Several
entries across several tasks are needed before the number means anything.

### The half not yet scoped

L4's second half is test economics: record/replay cassettes for the app's own
LLM calls, a gateway test tier pointed at a local model, exit gate "the full
test suite runs at about $0". Also unscoped: the setup convergence path
(`ensure-dev.sh`, `preflight.sh`, seeded users, dev-login, unified logs) with
its gate "a cold sandbox reaches green tests via the setup script alone, no
human touch". That partly conflicts with the 22 Jul decision to bake deps into
the image, taken to keep the exploration number clean. Decide whether it is
deferred or dropped rather than letting it lapse.

## Repository layout (github.com/zohaibtanwir/waterline)

```
waterline/
├── README.md                     # L0/L1/L2 decisions + as-built
├── ARCHITECTURE.md               # agent-authored (task-001), high-level narrative
├── docs/
│   ├── runbook.md                # master sequence (start here)
│   ├── architecture.md           # THIS FILE — living, per-layer
│   ├── session-context.md        # how we work + where we are right now
│   ├── failure-log.md            # every failure + fix (evidence base, #1-17)
│   ├── change-log.md             # infra deltas as they happen
│   └── deferred.md               # the register: what/why/trigger per item
├── bin/
│   └── sandbox-run.sh            # lifecycle driver (v0.12.1)
├── keel/                         # KEEL — the harness base layer (v0.3)
│   ├── README.md                 # current release, install, promotion test, walls
│   ├── CONVENTIONS.md            # standing rules (the only context-charged file)
│   ├── settings.json             # permissions (v0.2), hook registration
│   ├── hooks/require-green.sh    # Stop gate (exit 2 on red; audits to out-mount)
│   ├── agents/verifier.md        # 11-shortcut adversarial diff check
│   └── bin/check-budget.sh       # assembled-context budget (soft 250 / hard 300)
├── tasks/                        # versioned task specs (target-keel-01..06, tc-01..06)
├── images/
│   └── sandbox-base/             # Dockerfile + managed-settings (the environment)
└── infra/controller/
    ├── provision-controller.sh   # phase 1: box (OS, tailscale, docker, proxy)
    ├── tinyproxy.conf / -filter  # egress allowlist
    ├── deploy/
    │   ├── deploy-langfuse.md     # phase 2: observability stack
    │   └── deploy-gateway.md      # phase 2: gateway stack
    ├── langfuse/                  # compose + clickhouse-memory.xml + .env.example
    └── gateway/                   # config.yaml + compose + .env.example
    (runner/ holds provision-runner.sh)
```

Target repos (github.com/zohaibtanwir/target-flaskapp,
github.com/zohaibtanwir/target-tripconcierge) are NOT substrate: they receive an
installed copy of Keel under `.claude/` plus their own CLAUDE.md local layer.

## Runner working layout (not in git — disposable / secrets)

```
/opt/waterline/
├── sandbox-run.sh           # deployed from repo bin/ (v0.12.1) — NOT under bin/
├── gateway-master.key       # 0600 — mints virtual keys; NEVER enters a sandbox
├── images/sandbox-base/     # deployed from repo
├── tasks/<id>.json          # deployed task specs (repo is the author surface)
├── results/<id>.json        # result records
└── sandboxes/<id>/          # per-task: clone, changes.diff, out/
    └── out/
        ├── claude-stream.jsonl          # every turn, every tool call
        ├── claude-output.json           # derived: last result line of the stream
        ├── claude-stderr.log
        ├── keel-gate.log                # one line per gate firing
        ├── gateway-spend-timeline.jsonl # ledger sampled every 30s
        ├── gateway-key-info.json        # captured before revocation
        ├── gateway-spend-logs.json      # per-request rows, before revocation
        └── gateway-key-delete.json
/root/.git-credentials       # 0600 — repo-scoped PAT (host only)
/opt/waterline-repo/         # repo clone (pull to sync) — the DEPLOY SOURCE
```

The cloned target survives each run at `sandboxes/<id>/repo/`: destroy removes
the container, not the workdir, and the workdir is cleared only at the start of
the next run of that same task id. It is the best artifact for any "what did the
agent actually read" question.

## Known debt

Canonical register: **docs/deferred.md** (what/why/trigger per item). Headlines:

- The pass-through model bypass — `ANTHROPIC_MODEL` steers but does not
  constrain; 10% of tc-05's spend went to a model the task never asked for.
- tc-04's phantom 429 — enforcement refused at a number present in no record.
  Three hypotheses falsified; audit capture is in place for the next occurrence.
- Per-tier cost attribution through the alias does not work → L8.
- Model name still absent from Langfuse traces (result record carries it) → L8.
- The eight surviving Keel deny entries have never fired in any run.
- Keel's two-walls documentation still describes speed bumps as walls.
- Door 1 has no file-write boundary and no container.
- L3's removal diagnostic has never been run.
- No Keel installer or drift detection; four manual copies done, case made.
- gVisor runtime slot designed, not enabled → regulated-client hardening.
- Fleet: runner #1 hand-built; bootstrap-runner.sh → L6.
- Secrets in plaintext .env (0600, tailnet-only) → vault/sops at first client review.
