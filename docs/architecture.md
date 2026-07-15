# Waterline — architecture

Living document. Updated at the close of each layer. Current as of **L1 close (15 Jul 2026)**.

> Maintenance rule: this file is a close-out deliverable. At each layer's close,
> update the diagram, the component status table, and the file trees to match
> what was actually built — then commit. It documents *state*, so it must never
> lag the boxes. When a component moves from planned to built, flip its status
> and add its files to the trees below.

## Layer status

| Layer | Scope | Status |
|-------|-------|--------|
| L0 | Infrastructure — two hardened boxes, tailnet-only | ✅ built |
| L1 | Containment & execution — sandboxes, proxy, lifecycle | ✅ built |
| L2 | Gateway & routing — LiteLLM, virtual keys, model routing | ⏳ next |
| L3 | Harness — the 7 files on a real repo | ☐ planned |
| L4 | Codebase legibility + test economics | ☐ planned |
| L5 | Knowledge & memory — skills marketplace, learning capture | ☐ planned |
| L6 | Dispatcher & channels — Telegram/Slack | ☐ planned |
| L7 | Gates & review — CI, review agents, artifact gates | ☐ planned |
| L8 | Observability & economics — Langfuse, cost dashboards | ☐ planned |
| L9 | Validation — real task runs, failure log at scale | ☐ planned |

## System diagram

```
                        Your Mac
                   Tailscale SSH only
                          |
              tailnet (100.x) — no public ports
              |                              |
              v                              v
  +===============================+   +==================================+
  |  waterline-control            |   |  waterline-runner-1              |
  |  100.98.245.52 · durable      |   |  100.109.125.122 · disposable    |
  |  Netcup VPS 2000 · 16GB       |   |  Netcup VPS 1000 · 8GB           |
  |                               |   |                                  |
  |  [LIVE] tinyproxy :8888       |   |  [BUILT] sandbox-run.sh v0.2     |
  |    allowlist + audit log      |   |    create·inject·exec·harvest·   |
  |                               |   |    destroy                       |
  |  [L2]  gateway (LiteLLM)      |   |                                  |
  |    virtual keys · routing     |   |  [BUILT] sandbox-base:v0 image   |
  |                               |   |    Claude Code 2.1.210 (pinned)  |
  |  [L6/L8] Langfuse·dispatcher  |   |    baked deny-floor · proxy env  |
  |                               |   |                                  |
  |  agent code NEVER runs here   |   |  sandbox-net 172.30.0.0/24       |
  +==============|================+   |    iptables → controller ONLY    |
                 ^                    |   +--------------------------+   |
                 |                    |   | sbx-<task> (per task)    |   |
     all sandbox egress              |   | non-root · capped · dies |   |
     (only path out)                 |   +--------------------------+   |
                 |                    +===========|======================+
                 |                                |
                 +--------------------------------+
                                 |
                    +------------+------------+
                    v                         v
         allowlisted internet          Anthropic API
         github · pypi · npm           (direct now →
         (logged)                       via gateway at L2)
```

Trust is one-way: the controller dispatches work **down** to runners; agent-generated
code never flows **up** to the controller. Sandbox egress has exactly one path out —
through the controller's proxy — and the proxy allowlist decides what of the internet
that path can reach. Direct sandbox→internet is blocked by iptables.

## Boxes

### waterline-control (controller)
Durable, stateful, holds all credentials and knowledge. Never executes agent code.

- **tinyproxy :8888** — extended-regex allowlist (github, pypi, npm; interim api.anthropic.com), every request logged to `/var/log/tinyproxy/tinyproxy.log` (the audit trail)
- **gateway (L2)** — LiteLLM: virtual keys, model routing, budgets
- **Langfuse / dispatcher (L6/L8)** — traces, task intake

### waterline-runner-1 (runner)
Disposable, hourly-billed. All agent execution happens here. Deleted when idle;
respawned from `provision-runner.sh`.

- **Docker + sandbox-net** — bridge 172.30.0.0/24; DOCKER-USER iptables lock egress to controller only
- **sandbox-base:v0** — the declared environment (see image recipe)
- **sandbox-run.sh v0.2** — the lifecycle driver

## Lifecycle: create → inject → exec → harvest → destroy

1. **create** — fresh container from `sandbox-base:v0` on sandbox-net, with caps (timeout/mem/cpus)
2. **inject** — host clones repo (host holds the git PAT; sandbox never does), chowns to agent uid, mounts into container; task prompt + model key passed via env
3. **exec** — `claude -p` runs headless as non-root `agent`; walls not prompts (containment does the permission job)
4. **harvest** — host (outside the container) computes the diff, writes the result record; in later layers, pushes the branch and opens the PR
5. **destroy** — container removed; only the harvested artifacts survive; state lives on the host/controller, never in the sandbox

## Repository layout (github.com/zohaibtanwir/waterline)

```
waterline/
├── README.md                     # L0 + L1 decisions and as-built
├── ARCHITECTURE.md               # agent-authored (task-001), high-level narrative
├── docs/
│   ├── architecture.md           # THIS FILE — living, updated per layer
│   └── failure-log.md            # every failure, layer, fix — the evidence base
├── bin/
│   └── sandbox-run.sh            # lifecycle driver (v0.2)
├── images/
│   └── sandbox-base/
│       ├── Dockerfile            # the declared environment
│       └── managed-settings.json # baked deny-floor
└── infra/
    ├── controller/
    │   ├── provision-controller.sh
    │   ├── tinyproxy.conf
    │   └── tinyproxy-filter       # THE allowlist
    └── runner/
        └── provision-runner.sh
```

## Runner working layout (not in git — disposable / secrets)

```
/opt/waterline/
├── sandbox-run.sh                # deployed from repo bin/
├── task.env                      # 0600 — interim model key (dies at L2)
├── images/sandbox-base/          # deployed from repo images/
├── tasks/<id>.json               # task specs
├── results/<id>.json             # result records
└── sandboxes/<id>/               # per-task: repo clone, changes.diff, docker.log
/root/.git-credentials            # 0600 — repo-scoped PAT (host only, never in sandbox)
```

## Known debt (tracked in failure-log.md)

- Interim direct Anthropic key → replace with L2 gateway virtual keys, then revoke `waterline-interim`
- Agent telemetry files (`.claude-output.json`, `.claude-stderr.log`) land inside repo diff → v0.3 separate out-mount
- Docker runtime is plain; gVisor slot designed in but not enabled (regulated-client hardening)
