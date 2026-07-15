# Failure log

Every failure, its layer, diagnosis, and the fix's landing place. This log is
a first-class deliverable: it is the evidence base the client-facing
substrate inherits.

| # | Date | Stage | Failure | Layer | Fix | Landed in |
|---|------|-------|---------|-------|-----|-----------|
| 1 | 15 Jul | inject | Private repo clone prompted interactively; password auth dead on GitHub; set -e killed session | infra (credentials) | Fine-grained PAT (repo-scoped, 90d) in /root/.git-credentials on runner host; GIT_TERMINAL_PROMPT=0 | sandbox-run.sh v0.1; provision-runner.sh notes |
| 2 | 15 Jul | exec | Agent could not reach model API — containment blocked api.anthropic.com on both paths (iptables + proxy filter) | infra (network policy) | Allowlisted ^api\.anthropic\.com$ in tinyproxy filter (interim until L2 gateway carries model traffic) | infra/controller/tinyproxy-filter |
| 3 | 15 Jul | harvest | Zero-change run: grep -v exited 1, pipefail killed script before destroy; container leaked | script bug | grep -cv … \|\| true; pre-flight cleanup of leftovers | sandbox-run.sh v0.1/v0.2 |
| 4 | 15 Jul | exec | Permission denied on first write: host cloned as root, agent runs as uid 1001 across mount boundary | script bug (mount/uid) | chown -R 1001:1001 after clone; safe.directory for root-side harvest | sandbox-run.sh v0.2 |
| 5 | 15 Jul | harvest | .claude-output.json / .claude-stderr.log land inside repo diff; would pollute future PR pushes | hygiene (open) | PLANNED: separate /workspace/out mount for agent telemetry | pending — v0.3 |

Diagnosis discipline (from the harness article): name the layer first —
harness/infra failures (permissions, network, credentials) vs loop failures
(agent never converges, verification passes garbage). Entries 1–5 are all
infra/script layer; no agent-behavior failures yet.
