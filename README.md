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