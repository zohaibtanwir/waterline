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
| 17 Jul | controller | Removed api.anthropic.com line from tinyproxy filter; restarted | Model traffic is gateway-direct now, not through the sandbox proxy path — the L1 interim hole is closed | infra/controller/tinyproxy-filter (synced) |
| 17 Jul | external | Revoked waterline-interim Anthropic key in console | Superseded by waterline-gateway (the one real key, on the controller); L2 exit gate | N/A |
| 17 Jul | external | Created target repo github.com/zohaibtanwir/target-flaskapp (seeded from aaronjolson/flask-pytest-example, clean history) | L3 proving ground. Deliberately a SEPARATE repo: it is a *target*, not substrate — mirrors the real engagement shape (our IP installs into a client repo). Naming: target-<name>. | N/A — targets are not provisioned |
| 18 Jul | runner | Deployed sandbox-run.sh v0.4 | Out-mount for agent report; venv/caches to unmounted paths (die with container); harvest excludes; "mount":"ro"\|"rw" task-spec field; result record gains report_path + summary. Fixes failure-log #5. | bin/sandbox-run.sh (repo) |
| 18 Jul | repo | Task specs are SUBSTRATE — versioned in tasks/, not authored on the box | The "mount":"ro" choice for target-smoke was a deliberate design decision; decisions belong in git, not on a disposable runner | tasks/target-smoke.json |
| 19 Jul | repo | Keel v0.1 authored in keel/ (CONVENTIONS.md, settings.json, hooks/require-green.sh, agents/verifier.md, README) | L3 harness base layer — versioned substrate IP that installs into target repos | keel/ (repo) |
| 19 Jul | external | Keel v0.1 installed into target-flaskapp + CLAUDE.md local layer (9e1f7b2) | First install. Layout decision: settings.json + verifier at standard .claude/ discovery paths; conventions + hook nested under .claude/keel/ | Manual — install steps ARE the spec for the future installer (deferred) |
| 19 Jul | runner | Deployed sandbox-run.sh v0.5 | Per-task "env" object from task spec injected into container — transport for KEEL_TEST_CMD (and later ANTHROPIC_MODEL) without editing managed files | bin/sandbox-run.sh |
| 20 Jul | repo + external | Keel v0.1.1; target upgraded (ee162b1) | Durability rule ("the diff is the deliverable" — closes run-03 ephemeral-fix loophole); gate audits every firing to /workspace/out/keel-gate.log | keel/; manual upgrade #1 |
| 20 Jul | runner | Deployed sandbox-run.sh v0.6 | Result record self-reports model + model_usage lifted from agent report (closes the model-evidence gap without touching Langfuse); env count fix | bin/sandbox-run.sh |
| 20 Jul | repo + external | Keel v0.1.2; target upgraded | Verifier upgraded to full 11-shortcut catalogue (sourced: moonrunnerkc/swarm-orchestrator); deny patterns corrected to //** (absolute form); two-walls README; NEW bin/check-budget.sh (assembled-context budget, soft 250 / hard 300) | keel/; manual upgrade #2 |
| 20 Jul | repo | Keel v0.1.3 (README only) | Two-walls corrected to verified facts after probe 06: denies bind on both doors incl Bash-redirect inspection; run-05 failure was an invalid pattern silently ignored. Header convention: file headers = last-changed version | keel/README.md |
| 20 Jul | repo | Tasks target-keel-01..06 versioned in tasks/ | Probes are substrate: each task spec encodes a designed experiment (gate probe, routing A/B, deny probes) and its caps/mount/env decisions | tasks/ |
| 22 Jul | repo | docs corrected before any new run: architecture.md re-marked claim-by-claim with evidence; exit gate 2 restated as NOT MET AS STATED; tier economics withdrawn; tc-01 added to evidence table as VOID | Trust defect (failure-log #13) invalidated the L3 evidence base. Documents corrected first, on the rule that a wrong claim in a canonical doc costs more than a delayed run | docs/architecture.md; docs/failure-log.md |
| 22 Jul | repo | Keel v0.1.4 (README only) | Same corrections at the Keel layer: two-walls section rewritten with what proves each wall; honest Known-Open stating that until the trust fix ships only CONVENTIONS.md and check-budget.sh demonstrably function in a sandbox | keel/README.md |
| 22 Jul | repo | deferred.md +2 entries: workspace trust (trigger FIRED, blocking); tier pass-through trade-off | Both were discovered as blocking findings during the reconciliation and needed triggers before they could be deferred honestly | docs/deferred.md |
| 22 Jul | runner | Built sandbox-base:v1 | L4 prerequisite: bake deps (uv 0.11.31, pnpm 11.15.1) so the baseline measures codebase-understanding cost, not dependency-install cost. v0 had neither | images/sandbox-base/ |
| 22 Jul | runner | sandbox-base:v1 rebuilt — corepack replaced with npm install -g pnpm@VERSION; both tool versions now ASSERTED at build, not printed | corepack silently resolved the pnpm pin forward (11.15.1 asked, 11.16.0 got) while the build stayed green — sixth instance of the silent-success failure shape. A drifted pin now fails the BUILD, not a run | images/sandbox-base/Dockerfile |
| 22 Jul | runner | Built sandbox-base:v2 | Writes /home/agent/.claude.json with projects["/workspace/repo"].hasTrustDialogAccepted=true, asserted at build. This is the fix for failure-log #13 — workspace trust is environment state, so it belongs in the image, not the repo | images/sandbox-base/ |
| 22 Jul | runner | Deployed sandbox-run.sh v0.7 | num_turns into the result record (needed for the L4 autopsy); hardened spend poll against the async-ledger under-report | bin/sandbox-run.sh |
| 22 Jul | runner | Deployed sandbox-run.sh v0.9 | TRUST PREFLIGHT: refuses to start (exit 3) on an image that does not mark the workspace trusted. Harvest greps agent stderr for the trust warning and records settings_loaded in the result record — turns a log line nobody read into a field we always read. Default image deliberately left at :v1 so nothing switches silently | bin/sandbox-run.sh |
| 22 Jul | external | Created target repo github.com/zohaibtanwir/target-tripconcierge (private) | L4 proving ground — a real application rather than a 110-line toy. Seeded from the working tree, secrets scanned (web/.env.local + backend/.env removed), vendored .venv/node_modules pruned. 320 files, 5.8M | N/A — targets are not provisioned |
| 22 Jul | repo | Keel v0.1.5 then v0.1.6 | Door-1 isolation tests (free, interactive, no API spend) showed Write(//**) is an INVALID form that Claude Code ignores — its own startup warning says only Edit(path) rules are matched by file permission checks. v0.1.5 removed both file-deny lines to isolate; that proved the working-directory boundary only PROMPTS, it does not deny. v0.1.6 restores Edit(//**) as the real enforcing rule and leaves Write(//**) out | keel/settings.json |
| 23 Jul | repo | Task target-tc-03 authored and versioned | Probe: do Keel's deny rules bite in a sandbox now that settings load. Designed against the image's managed-settings deny list to be DISJOINT from it — the image has no Edit rule, so an Edit refusal can only come from Keel | tasks/target-tc-03.json |
| 24 Jul | runner | Deployed sandbox-run.sh v0.10 | Captures claude -p --output-format stream-json --verbose to claude-stream.jsonl; derives claude-output.json from the LAST "type":"result" line, not tail -1 — a host-timeout kill leaves no result line and tail would grab a mid-stream object that parses to nulls. Closes the transcript-capture gap that made the L4 autopsy impossible and wasted tc-01 | bin/sandbox-run.sh |
| 24 Jul | repo | Task target-tc-04 authored and versioned | L4 baseline re-run: tc-01 prompt verbatim, sandbox-base:v2 named explicitly (default is still :v1), mount rw, ANTHROPIC_MODEL execute, KEEL_TEST_CMD set, budget_usd 5, timeout 2700 | tasks/target-tc-04.json |
| 24 Jul | runner | Deployed sandbox-run.sh v0.10 | Captures claude -p --output-format stream-json --verbose to claude-stream.jsonl; derives claude-output.json from the LAST "type":"result" line, not tail -1 — a host-timeout kill leaves no result line and tail would grab a mid-stream object that parses to nulls. Closes the transcript-capture gap that wasted tc-01 | bin/sandbox-run.sh |
| 24 Jul | repo | Task target-tc-04 authored and versioned | L4 baseline re-run: tc-01 prompt verbatim, sandbox-base:v2 named explicitly, mount rw, ANTHROPIC_MODEL execute, KEEL_TEST_CMD set, budget_usd 5, timeout 2700 | tasks/target-tc-04.json |
| 25 Jul | repo | Keel v0.2 — Edit(//**) removed | tc-04 stream shows the rule denying the agent its OWN task path (/workspace/repo/agents/tests/test_tasks.py) and the agent routing around it with cat and python3 in the same turn, twice. //** matches every absolute path including the target repo, so the rule cannot be narrowed to "outside the repo" — deny beats allow, which the file already assumes via Read(*) allow plus Read(./.env) deny. Secret and destructive-Bash denies retained as speed bumps, not walls. README header v0.1.4 to v0.2 in the same touch, clearing the recorded drift | keel/settings.json; keel/README.md |

## Paper-trail note (24 Jul)

This log ran three days behind between 20 and 24 Jul while architecture.md and
failure-log.md were kept current. The log is the running delta between layer
closes, so a gap here is a gap in the only record of what changed on the boxes
between two close-out snapshots. Update it in the same commit as the change,
not at the next layer close.

## Deployment model (established at L2)
Two phases with a clean boundary:
- **provision-*.sh** = make a box into a controller/runner (OS, Tailscale, Docker,
  proxy/sandbox-net). Run once per box. Infrastructure.
- **deploy/deploy-*.md** = bring up a service stack on a provisioned box
  (Langfuse, gateway). Per-service, re-runnable. Application deployment.
Master sequence across both: docs/runbook.md.

## Task specs (established at L3)
Task specs live in `tasks/` in the repo and are deployed to the runner like any
other artifact. They encode decisions (mount mode, caps, budget), so they are
versioned. Runner-side `/opt/waterline/tasks/` is a deployment target, not a
place to author.

