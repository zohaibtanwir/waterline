# Waterline — architecture

Living document. Updated at the close of each layer. Current as of **L3 close (20 Jul 2026)**.

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
| L4 | Codebase legibility + test economics | ☐ planned — scope to be debated at open |
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
  |  [LIVE] tinyproxy :8888         |   |  [LIVE] sandbox-run.sh v0.6      |
  |    allowlist (github/pypi/npm)  |   |    mint→inject→exec→harvest→      |
  |    api.anthropic.com REMOVED    |   |    destroy(+revoke vkey)         |
  |                                 |   |    task-spec env injection;      |
  |  [LIVE] LiteLLM gateway :4000   |   |    result self-reports model     |
  |    v1.89.0 · real Anthropic key |   |                                  |
  |    tier aliases plan/exec/verify|   |  [LIVE] sandbox-base:v0 image    |
  |    (wired at L3: task-spec      |   |    Claude Code 2.1.210 pinned    |
  |     ANTHROPIC_MODEL=alias)      |   |                                  |
  |    mints per-task virtual keys  |   |  sandbox-net 172.30.0.0/24       |
  |                                 |   |    iptables → controller ONLY    |
  |  [LIVE] Langfuse :3000 (6 svc)  |   |   +--------------------------+   |
  |    traces + per-task cost       |   |   | sbx-<task> (per task)    |   |
  |                                 |   |   | holds ONLY a virtual key |   |
  |  agent code NEVER runs here     |   |   | Keel-governed (target)   |   |
  +==========|=============^========+   |   | non-root · capped · dies |   |
             ^             |            |   +--------------------------+   |
             |             |            +======|=================|=========+
   model calls (:4000)  admin: mint/revoke     |                 |
   virtual key          via master key on      | git/pkg (:8888) | model (:4000)
             |          runner HOST            | via proxy       | via virtual key
             +---------------------+           v                 |
                                   |     allowlisted internet    |
                                   |     github · pypi · npm     |
                                   +------------- Anthropic API <+
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
  per-task virtual key →  SANDBOX only               (budget-capped $1, revoked
                                                       at destroy — a dead ticket)
```

A fully compromised sandbox yields only a spent, budget-capped virtual key.

## Lifecycle: mint → inject → exec → harvest → destroy  (v0.6)

1. **mint** — runner calls gateway /key/generate (master key) → per-task virtual key, budget-capped
2. **inject** — host clones repo (host holds git PAT), chowns to agent uid, mounts in:
   repo (ro|rw per task spec) + a separate out-mount for report/audit; task-spec
   `env` object injected as container environment (KEEL_TEST_CMD, ANTHROPIC_MODEL)
3. **exec** — claude -p as non-root; ANTHROPIC_BASE_URL→gateway, ANTHROPIC_API_KEY=virtual key;
   venv/caches on unmounted paths — they die with the container
4. **harvest** — host computes diff (excludes as safety net) + result record; lifts
   model + model_usage from the agent report; reads spend_usd from gateway
   (known gap: ledger is async — under-reports on sub-15s runs; see deferred)
5. **destroy** — container removed AND virtual key revoked

## L3 — the harness (as built, closed 20 Jul 2026)

L3 answers the question the layers below cannot: is the work real? L0-L2
contain the agent and meter it; L3 governs it. The deliverable is **Keel** —
a versioned base layer of working rules and mechanical gates that installs
into any target repo — proven on target-flaskapp across six instrumented runs.

### The two-layer model

```
            KEEL  (versioned base -- substrate IP, waterline/keel/)
            CONVENTIONS.md  settings.json  hooks/require-green.sh
            agents/verifier.md  bin/check-budget.sh        v0.1.3
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
   interactive; prompts + denies live    headless; denies + container wall
```

Base is ours and versioned (MAJOR/MINOR/PATCH; file headers record the
version at which each file last changed). Local is theirs. The seam is an
import plus a merge — upgrades are file swaps, never re-derivation. Backflow
is governed by the promotion test (true on 2+ repos; mechanism not codebase
fact; displaces something).

### The two walls

Protection is layered and was probe-verified on both doors:

- **Permission rules** bind interactively AND in headless skip-permissions
  runs — including Bash-redirect inspection against file-deny rules — when
  the pattern is valid. An invalid pattern is silently ignored (failure-log
  #12): a deny is not deployed until a probe has watched it refuse.
- **The container boundary** (ro/scoped mounts, unmounted scratch, allowlist
  network) held in every run, including the five during which the config wall
  was silently absent. The walls fail independently; that is why there are two.

### Done means verified

- The Stop gate (`require-green.sh`) refuses the agent's finish on a red
  suite (exit 2), allows one retry, then releases loudly as UNVERIFIED.
  All three branches observed in production; every firing audited to
  /workspace/out/keel-gate.log.
- The diff is the deliverable: a fix that lives only in the disposable
  environment does not count (rule added in v0.1.1 after run 03 produced
  green tests with an empty diff).
- The verifier subagent carries the full 11-shortcut fake-done catalogue
  (sourced from a 327-PR mining study). Flags are tips; the gate and the
  human are the deciders.
- The assembled standing context (CLAUDE.md + imports) is budget-checked
  mechanically: soft 250 lines, hard 300 (bin/check-budget.sh).

### Tier routing

One line in the task spec — `"env": {"ANTHROPIC_MODEL": "execute"}` — routes
through the L2 gateway aliases. Honest economics from the A/B: a durable fix
on the execute tier cost $0.78/390s vs $0.99/243s on the plan tier — 21%
cheaper, 60% slower. Tier economics are per-task-type, not per-model; the
gateway ledger is the only quotable cost (agent-side pricing is unreliable
with aliases, and the ledger itself under-reports on sub-15s runs — see
deferred: async spend ledger).

### Evidence (runs 01-06)

| Run | Question | Answer |
|---|---|---|
| 01 | Does a real bug get fixed under the rules? | Yes — cause not tests, 3 files, $0.99 (Opus) |
| 02 | Is the Stop gate wired? | Yes — rigged-to-fail task; refusal, retry, loud release |
| 03 | Does tier routing work? | Yes — and exposed the ephemeral-fix loophole (green, empty diff) |
| 04 | Does the durability rule close it? | Yes — same fix as Opus, in the tree, $0.78 (Sonnet) |
| 05 | Does the write-deny hold? | No — invalid pattern silently ignored; container held |
| 06 | Does the corrected deny hold? | Yes — Write AND Bash redirect denied, recorded |

### Exit gates (all met)

1. Keel installed in a real target; a genuine pre-existing bug fixed under
   its rules with the diff as deliverable.
2. Every harness mechanism verified by direct probe on both doors — zero
   claims resting on inference.
3. Tier routing wired end to end with measured economics.
4. Context budget mechanically enforced.
5. Paper trail current: change-log, failure-log (#10-12), deferred register,
   Keel changelog v0.1 -> v0.1.3.

### Carried forward (open by choice, with triggers — see docs/deferred.md)

- Verifier invocation evidence (checklist complete; no run has yet required
  the verifier).
- L3/L5 skills boundary (decides with the org-evolution research pass).
- Loop runner: deferred to the future, assigned to NO layer — its adoption
  and placement require their own debate first.

## Repository layout (github.com/zohaibtanwir/waterline)

```
waterline/
├── README.md                     # L0/L1/L2 decisions + as-built
├── ARCHITECTURE.md               # agent-authored (task-001), high-level narrative
├── docs/
│   ├── runbook.md                # master sequence (start here)
│   ├── architecture.md           # THIS FILE — living, per-layer
│   ├── failure-log.md            # every failure + fix (evidence base, #1-12)
│   ├── change-log.md             # infra deltas as they happen
│   └── deferred.md               # the register: what/why/trigger per item
├── bin/
│   └── sandbox-run.sh            # lifecycle driver (v0.6 — env injection, model harvest)
├── keel/                         # KEEL — the harness base layer (v0.1.3)
│   ├── README.md                 # current release, install, promotion test, two walls
│   ├── CONVENTIONS.md            # standing rules (the only context-charged file)
│   ├── settings.json             # permissions (deny //**), hook registration
│   ├── hooks/require-green.sh    # Stop gate (exit 2 on red; audits to out-mount)
│   ├── agents/verifier.md        # 11-shortcut adversarial diff check
│   └── bin/check-budget.sh       # assembled-context budget (soft 250 / hard 300)
├── tasks/                        # versioned task specs incl probes (target-keel-01..06)
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

Target repos (e.g. github.com/zohaibtanwir/target-flaskapp) are NOT substrate:
they receive an installed copy of Keel under .claude/ plus their own CLAUDE.md
local layer.

## Runner working layout (not in git — disposable / secrets)

```
/opt/waterline/
├── sandbox-run.sh           # deployed from repo bin/ (v0.6)
├── gateway-master.key       # 0600 — mints virtual keys; NEVER enters a sandbox
├── images/sandbox-base/     # deployed from repo
├── tasks/<id>.json          # deployed task specs (repo is the author surface)
├── results/<id>.json        # result records (spend_usd, model, model_usage)
└── sandboxes/<id>/          # per-task: clone, changes.diff, out/ (report + keel-gate.log)
/root/.git-credentials       # 0600 — repo-scoped PAT (host only)
/opt/waterline-repo/         # repo clone (pull to sync)
```

## Known debt
Canonical register: **docs/deferred.md** (what/why/trigger per item). Headlines:
- Async spend ledger: gateway under-reports on sub-15s runs → sandbox-run v0.7.
- Model name still absent from Langfuse traces (result record now carries it) → L8.
- No Keel installer or drift detection; three manual copies done, case made.
- gVisor runtime slot designed, not enabled → regulated-client hardening.
- Fleet: runner #1 hand-built; bootstrap-runner.sh → L6.
- Secrets in plaintext .env (0600, tailnet-only) → vault/sops at first client review.
