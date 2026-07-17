# Waterline — master runbook

**Start here.** This is the ordered sequence to stand up the entire waterline
substrate from nothing. It delegates to detailed docs/scripts rather than
repeating them — follow each step, verify its exit gate, move on.

Living doc: updated at each layer close as new steps are added.
Current coverage: **L0–L2 complete. L3 (harness) next.**

Convention: every command is labeled with where it runs — MAC, CONTROLLER,
or RUNNER. Never run a box-boundary command on the wrong box (read the prompt).

---

## Prerequisites (one-time, on your Mac)

- A Tailscale account; `tag:substrate` defined in the ACL, admin→substrate SSH rule.
- An SSH keypair for the lab (e.g. `~/.ssh/waterline`), public half registered in the Netcup SCP.
- A GitHub fine-grained PAT scoped to the `waterline` repo (Contents: read/write).
- An Anthropic **workspace** with a spend limit, and a key minted inside it (`waterline-gateway`).

---

## Step 1 — Provision the controller box

1. Netcup SCP: order a VPS (hourly), reinstall image → Ubuntu 24.04 minimal,
   inject the `waterline` SSH key, disable password auth. Hostname `waterline-control`.
2. Generate a single-use, tagged (`tag:substrate`) Tailscale auth key.
3. **MAC:** scp provision-controller.sh (+ tinyproxy.conf, tinyproxy-filter) to the box.
   **CONTROLLER:** `bash provision-controller.sh <tailscale-auth-key>`
4. **Exit gate:** tailnet SSH works from the Mac; apply the firewall block the
   script prints; public SSH times out.

## Step 2 — Provision the runner box

1. Order VPS (hourly), reinstall Ubuntu 24.04 minimal + key, hostname `waterline-runner-1`.
2. Fresh single-use tagged Tailscale key.
3. **RUNNER:** `bash provision-runner.sh <ts-auth-key> <controller-tailnet-ip>`
4. Deploy `bin/sandbox-run.sh` to `/opt/waterline/`; build the sandbox image
   (`images/sandbox-base`). Place host-only secrets: `/opt/waterline/task.env`
   (legacy; superseded by gateway), `/root/.git-credentials` (0600).
5. **Exit gate:** tailnet SSH works, public SSH times out; three-probe containment
   test passes (direct blocked / proxy-allowed 200 / proxy-denied refused).

## Step 3 — Deploy Langfuse (observability)  [controller]  ✅

Follow **`infra/controller/deploy/deploy-langfuse.md`**.
**Exit gate:** `http://<controller-tailnet-ip>:3000` returns 200; Waterline org +
Waterline Lab project exist (auto-created via init vars).

## Step 4 — Deploy the gateway (LiteLLM)  [controller]  ✅

Follow **`infra/controller/deploy/deploy-gateway.md`**.
**Exit gate:** health endpoints green; virtual-key mint→call→revoke works; trace
appears in Langfuse. Then wire the runner: place `/opt/waterline/gateway-master.key`,
deploy sandbox-run.sh v0.3. Retire the interim path: revoke waterline-interim,
remove the tinyproxy api.anthropic.com line.

## Step 5 — Run a task (end-to-end)  [runner]  ✅

**RUNNER:** `/opt/waterline/sandbox-run.sh /opt/waterline/tasks/<task>.json`
**Exit gate:** result record shows `status: completed` with `spend_usd` populated
(read from the gateway); the trace is visible in Langfuse. (Proven: task-001 via
v0.3 — completed, 41s, $0.226 spend, trace logged.)

## Step 6 — (L3+) Harness, tier-routing, legibility  ☐ next

Not yet built. L3 gives task specs the richness to *request a routing tier*
(plan/execute/verify) rather than letting Claude Code pick its own model —
closing the gap where the gateway CAN route by tier but real tasks don't yet.

---

## Reference

- Architecture (living state + diagrams): `docs/architecture.md`
- Failures + fixes (evidence base): `docs/failure-log.md`
- Infra deltas (as they happen): `docs/change-log.md`
- Layer decisions + as-built: `README.md`
