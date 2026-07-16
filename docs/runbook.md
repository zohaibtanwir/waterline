# Waterline — master runbook

**Start here.** This is the ordered sequence to stand up the entire waterline
substrate from nothing. It delegates to detailed docs/scripts rather than
repeating them — follow each step, verify its exit gate, move on.

Living doc: updated at each layer close as new steps are added.
Current coverage: **L0–L2 (L2 in progress — Langfuse done, gateway next)**.

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
   inject the `waterline` SSH key, disable password auth. Set hostname
   `waterline-control`. (See README "L0 — As built" for the exact image-install settings.)
2. Generate a single-use, tagged (`tag:substrate`) Tailscale auth key.
3. Deploy the repo's provisioning script and run it:
   - **MAC:** `scp infra/controller/provision-controller.sh root@<public-ip>:/root/`
     (plus `tinyproxy.conf` and `tinyproxy-filter` from the same folder)
   - **CONTROLLER:** `bash provision-controller.sh <tailscale-auth-key>`
4. **Exit gate:** tailnet SSH works from the Mac; then apply the firewall block
   the script prints (UFW default-deny, allow tailscale0); public SSH must time out.

## Step 2 — Provision the runner box

Same shape as Step 1 with `provision-runner.sh` and hostname `waterline-runner-1`.

1. Order VPS (hourly), reinstall Ubuntu 24.04 minimal + key.
2. Fresh single-use tagged Tailscale key.
3. **RUNNER:** `bash provision-runner.sh <ts-auth-key> <controller-tailnet-ip>`
   (installs Docker, sandbox-net, the iptables egress lock, workspace dirs).
4. Deploy `bin/sandbox-run.sh` to `/opt/waterline/` and build the sandbox image
   (see `images/sandbox-base`). Place the two host-only secrets:
   `/opt/waterline/task.env` and `/root/.git-credentials` (both 0600).
5. **Exit gate:** tailnet SSH works, public SSH times out; the three-probe
   containment test passes (direct blocked / proxy-allowed 200 / proxy-denied refused).

## Step 3 — Deploy Langfuse (observability)  [controller]

Follow **`infra/controller/deploy/deploy-langfuse.md`**.
In brief: clone the repo to `/opt/waterline-repo`, fetch the upstream Langfuse
compose, apply our overrides, generate `.env` with fresh secrets, `docker compose up`.
**Exit gate:** `http://<controller-tailnet-ip>:3000` returns 200; the Waterline
org + Waterline Lab project exist (auto-created via init vars).

## Step 4 — Deploy the gateway (LiteLLM)  [controller]   ← NEXT (not yet built)

Follow `infra/controller/deploy/deploy-gateway.md` (to be written).
In brief: real Anthropic key + the Langfuse project keys into the gateway `.env`,
`docker compose up`, add the sandbox-net→controller:4000 iptables allow on the runner.
**Exit gate:** a task runs via the gateway; the sandbox holds only a virtual key;
the trace + per-task cost appear in Langfuse; `waterline-interim` revoked; the
tinyproxy `api.anthropic.com` allowlist line removed.

## Step 5 — Run a task (end-to-end)  [runner]

**RUNNER:** `/opt/waterline/sandbox-run.sh /opt/waterline/tasks/<task>.json`
**Exit gate:** result record shows `status: completed` with `spend_usd` populated;
the trace is visible in Langfuse.

---

## Reference

- Architecture (living state): `docs/architecture.md`
- Failures + fixes (evidence base): `docs/failure-log.md`
- Infra deltas (as they happen): `docs/change-log.md`
- Layer decisions + as-built: `README.md`
