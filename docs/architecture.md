# Waterline — architecture

Living document. Updated at the close of each layer. Current as of **L2 close (17 Jul 2026)**.

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
| L3 | Harness — the 7 files on a real repo; tier-routing wired | ⏳ next |
| L4 | Codebase legibility + test economics | ☐ planned |
| L5 | Knowledge & memory — skills marketplace, learning capture | ☐ planned |
| L6 | Dispatcher & channels — Telegram/Slack; runner fleet bootstrap | ☐ planned |
| L7 | Gates & review — CI, review agents, artifact gates | ☐ planned |
| L8 | Observability & economics — dashboards, model-name-in-traces gap | ☐ planned |
| L9 | Validation — real task runs, failure log at scale | ☐ planned |

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
  |  [LIVE] tinyproxy :8888         |   |  [LIVE] sandbox-run.sh v0.3      |
  |    allowlist (github/pypi/npm)  |   |    mint→inject→exec→harvest→      |
  |    api.anthropic.com REMOVED    |   |    destroy(+revoke vkey)         |
  |                                 |   |                                  |
  |  [LIVE] LiteLLM gateway :4000   |   |  [LIVE] sandbox-base:v0 image    |
  |    v1.89.0 · real Anthropic key |   |    Claude Code 2.1.210 pinned    |
  |    tier aliases plan/exec/verify|   |                                  |
  |    mints per-task virtual keys  |   |  sandbox-net 172.30.0.0/24       |
  |                                 |   |    iptables → controller ONLY    |
  |  [LIVE] Langfuse :3000 (6 svc)  |   |   +--------------------------+   |
  |    traces + per-task cost       |   |   | sbx-<task> (per task)    |   |
  |                                 |   |   | holds ONLY a virtual key |   |
  |  agent code NEVER runs here     |   |   | non-root · capped · dies |   |
  +==========|=============^========+   |   +--------------------------+   |
             ^             |            +======|=================|=========+
             |             |                   |                 |
   model calls (:4000)  admin: mint/revoke     | git/pkg (:8888) | model (:4000)
   virtual key          via master key on      | via proxy       | via virtual key
             |          runner HOST             v                 |
             +---------------------+     allowlisted internet      |
                                   |     github · pypi · npm       |
                                   +------------- Anthropic API <--+
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

## Lifecycle: mint → inject → exec → harvest → destroy  (v0.3)

1. **mint** — runner calls gateway /key/generate (master key) → per-task virtual key, $1 budget
2. **inject** — host clones repo (host holds git PAT), chowns to agent uid, mounts in
3. **exec** — claude -p as non-root; ANTHROPIC_BASE_URL→gateway, ANTHROPIC_API_KEY=virtual key
4. **harvest** — host computes diff + result record; reads spend_usd back from gateway
5. **destroy** — container removed AND virtual key revoked

## Repository layout (github.com/zohaibtanwir/waterline)

```
waterline/
├── README.md                     # L0/L1/L2 decisions + as-built
├── ARCHITECTURE.md               # agent-authored (task-001), high-level narrative
├── docs/
│   ├── runbook.md                # master sequence (start here)
│   ├── architecture.md           # THIS FILE — living, per-layer
│   ├── failure-log.md            # every failure + fix (evidence base)
│   └── change-log.md             # infra deltas as they happen
├── bin/
│   └── sandbox-run.sh            # lifecycle driver (v0.3 — virtual keys)
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

## Runner working layout (not in git — disposable / secrets)

```
/opt/waterline/
├── sandbox-run.sh           # deployed from repo bin/ (v0.3)
├── gateway-master.key       # 0600 — mints virtual keys; NEVER enters a sandbox
├── task.env                 # 0600 — legacy interim key path (now retired)
├── images/sandbox-base/     # deployed from repo
├── tasks/<id>.json          # task specs
├── results/<id>.json        # result records (now include spend_usd)
└── sandboxes/<id>/          # per-task: clone, changes.diff, docker.log
/root/.git-credentials       # 0600 — repo-scoped PAT (host only)
/opt/waterline-repo/         # repo clone (pull to sync)
```

## Known debt (tracked in change-log / deferred list)
- Tier-routing exists but unused: sandboxes use Claude Code's own model choice
  (pass-through), not our plan/execute/verify aliases → **L3** wires task-declared tiers.
- Model name not surfaced in Langfuse traces by LiteLLM integration → **L8**.
- Agent telemetry files land in repo diff → v0.3+ out-mount (hygiene).
- gVisor runtime slot designed, not enabled → regulated-client hardening.
- Fleet: runner #1 hand-built; bootstrap-runner.sh self-configuring script → **L6**.
- Tighter key model (runner asks controller to mint) → optional hardening.
