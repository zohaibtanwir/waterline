# waterline

Agentic engineering substrate — lab reference implementation.
The part of the iceberg below the surface.

## L0 — Decisions (locked 14 Jul 2026)

| Decision | Choice |
|---|---|
| Provider / box | Netcup VPS 2000 G12 (8 vCore, 16GB ECC, 512GB NVMe), Nuremberg, hourly |
| Host OS | Ubuntu 24.04 LTS |
| Networking | Tailscale-only ingress; UFW default-deny; no public ports |
| SSH | Tailscale SSH; key-only sshd as fallback (ed25519 `waterline` key) |
| Tailnet | Node tagged `tag:substrate`; admin→substrate SSH rule in ACL |
| Break-glass | Netcup SCP VNC console + rescue system (no cloud firewall exists) |
| Nix | Build tool only (sandbox images); host stays Ubuntu |
| Secrets | Plain 0600 files on controller at L0; sops/age at L2 |
| Repo | Single repo until L5 splits installable IP (`substrate`) out |

## Architecture

Controller (this box): gateway, observability, dispatcher, knowledge store.
Runner (future, hourly vServer): disposable per-task sandboxes. Nothing
agent-generated ever executes on the controller.

## Layers

L0 infra · L1 containment · L2 gateway/routing · L3 harness · L4 legibility
· L5 knowledge · L6 dispatch · L7 gates · L8 observability · L9 validation

## L0 — As built (14 Jul 2026)

- Box: Netcup VPS 2000 G12 (hourly), Nuremberg — `waterline-control`, 100.98.245.52 (tailnet)
- Install: SCP image install, Ubuntu 24.04.4 minimal, SSH key injected at
  install, password auth disabled from first boot (no retrofit needed)
- Primary access: Tailscale SSH (identity-based, ACL: admin → tag:substrate);
  key-based sshd remains as dormant fallback inside the tailnet
- Firewall: UFW active — deny in / allow out / allow in on tailscale0 only.
  Public SSH verified unreachable from outside
- Break-glass: SCP VNC console (root password in password manager) +
  SCP Firewall Policies exist as option B after all
- Timezone: UTC. Divergences from plan: panel key injection replaced the
  key-retrofit sequence; SCP has firewall + SSH-key features the plan assumed absent
## L1 — As built (15 Jul 2026)

- Runner: waterline-runner-1 (Netcup VPS 1000 G12, hourly), tailnet
  100.109.125.122, same hardening posture as controller
- Containment: Docker sandboxes on sandbox-net (172.30.0.0/24); iptables
  DOCKER-USER locks egress to controller only; proven by three-probe test
  (direct blocked / proxy-allowed 200 / proxy-denied refused)
- Egress proxy: tinyproxy on controller :8888, extended-regex allowlist
  (github, pypi, npm + interim api.anthropic.com), every request logged
- Sandbox image: waterline/sandbox-base:v0 — Ubuntu 24.04, Claude Code
  pinned 2.1.210, managed-settings deny-floor baked read-only, non-root
  agent (uid 1001), proxy env baked
- Lifecycle: bin/sandbox-run.sh v0.2 — create→inject→exec→harvest→destroy;
  caps as config (timeout/mem/cpus); result record JSON per task
- Credentials: sandboxes hold only a budget-capped model key (interim,
  dies at L2); git PAT lives on runner host only; harvest is external
- First run: task-001 — status completed, 32s, $0.11, 1 file changed;
  agent wrote ARCHITECTURE.md from inside the containment
- Known debt: interim Anthropic key → L2 virtual keys; agent telemetry
  files inside repo diff → v0.3 out-mount; see docs/failure-log.md


## L2 — As built (17 Jul 2026)

- **Langfuse v3** live on the controller (6 containers: web, worker, postgres,
  clickhouse, redis, minio), tailnet-bound at :3000, ClickHouse memory-capped.
  Deployed from upstream compose + our overrides (deploy/deploy-langfuse.md).
  Auto-bootstrapped org/project/admin + project keys via LANGFUSE_INIT_* vars.
- **LiteLLM gateway** live at :4000 — image pinned `litellm-database:v1.89.0`,
  own postgres for key store + spend ledger, LITELLM_SALT_KEY set, Langfuse
  logging wired (deploy/deploy-gateway.md).
- **Tier aliases** (the "ministry of experts"): plan→Opus, execute→Sonnet,
  verify→Haiku — plus pass-through for Claude Code's own model strings.
- **Per-task virtual keys**: sandbox-run.sh v0.3 mints a $1-budget key at create,
  passes it + the gateway base-URL into the sandbox, reads spend back at harvest,
  revokes at destroy. The sandbox holds no real credential.
- **Key model**: real Anthropic key → controller only; LiteLLM master key →
  controller + runner host (mints keys, never enters a sandbox); virtual key →
  sandbox only.
- **Proven end-to-end**: task-001 via v0.3 — status completed, 41s, spend_usd
  $0.226 (from the gateway ledger), trace + cost visible in Langfuse.
- **Interim path retired**: waterline-interim key revoked; tinyproxy
  api.anthropic.com line removed (model traffic is gateway-direct now).
- **L2 exit gate met.** Known debt → docs/architecture.md "Known debt".
