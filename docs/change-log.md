# Change log

Every deviation from documented box state, captured **when it happens** — not
reconstructed at layer close. The rule: if a command changes a box's durable
state, it gets a line here AND the relevant provisioning script is edited in the
same commit. This is the manual version of the L5 learning-capture hook.

Distinct from docs/failure-log.md (failures + fixes) and docs/architecture.md
(state at each layer close). This log is the running delta between them.

| Date | Box | Change | Why | Provisioning updated? |
|------|-----|--------|-----|----------------------|
| 16 Jul | controller | Installed Docker Engine + compose plugin | L2 makes the controller a container host (Langfuse + LiteLLM); L0/L1 only needed tinyproxy, so provision-controller.sh predated container-hosting | Yes — Docker block added to provision-controller.sh |
| 16 Jul | controller | Deployed Langfuse v3 stack (6 containers: web, worker, postgres, clickhouse, redis, minio), tailnet-bound, ClickHouse mem-capped | L2: observability pulled forward; per-task cost/traces from first gateway call | Deploy steps captured in deploy/deploy-langfuse.md (not in provision script — service deploy != box provisioning) |
| 16 Jul | repo | DECISION: Langfuse deployed from upstream compose + our overrides, not our hand-written compose | Upstream v3 evolved past a hand-reconstruction (extra vars, healthchecks); deriving from upstream inherits correctness. The committed langfuse/docker-compose.yml is now the upstream-derived, overrides-applied file. | N/A (pattern note) |
| 17 Jul | controller | Deployed LiteLLM gateway (litellm-database:v1.89.0 + own postgres) on :4000, tailnet-bound; Langfuse logging wired | L2: model routing + per-task virtual keys + spend tracking | deploy/deploy-gateway.md |
| 17 Jul | runner | Cloned repo to /opt/waterline-repo; deployed sandbox-run.sh v0.3; placed /opt/waterline/gateway-master.key (0600) | v0.3 mints/revokes per-task virtual keys against the gateway; runner host holds the master key (never enters a sandbox) | Manual for runner #1 — this IS the spec for the future bootstrap-runner.sh (fleet scaling) |
| 17 Jul | controller | Removed api.anthropic.com line from tinyproxy filter; restarted | Model traffic is gateway-direct now, not through the sandbox proxy path — the L1 interim hole is closed | infra/controller/tinyproxy-filter (repo copy to be synced) |
| 17 Jul | external | Revoked waterline-interim Anthropic key in console | Superseded by waterline-gateway (the one real key, on the controller); L2 exit gate | N/A |

## Deployment model (established at L2)
Two phases with a clean boundary:
- **provision-*.sh** = make a box into a controller/runner (OS, Tailscale, Docker,
  proxy/sandbox-net). Run once per box. Infrastructure.
- **deploy/deploy-*.md** = bring up a service stack on a provisioned box
  (Langfuse, gateway). Per-service, re-runnable. Application deployment.
Master sequence across both: docs/runbook.md.
