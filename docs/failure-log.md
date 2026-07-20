# Failure log

Every failure, its layer, diagnosis, and the fix's landing place. This log is
a first-class deliverable: it is the evidence base the client-facing
substrate inherits.

| # | Date | Stage | Failure | Layer | Fix | Landed in |
|---|------|-------|---------|-------|-----|-----------|
| 1 | 15 Jul | inject | Private repo clone prompted interactively; password auth dead on GitHub; set -e killed session | infra (credentials) | Fine-grained PAT (repo-scoped, 90d) in /root/.git-credentials on runner host; GIT_TERMINAL_PROMPT=0 | sandbox-run.sh v0.1; provision-runner.sh notes |
| 2 | 15 Jul | exec | Agent could not reach model API — containment blocked api.anthropic.com on both paths (iptables + proxy filter) | infra (network policy) | Allowlisted api.anthropic.com in tinyproxy filter (interim; removed at L2 when gateway-direct) | infra/controller/tinyproxy-filter |
| 3 | 15 Jul | harvest | Zero-change run: grep -v exited 1, pipefail killed script before destroy; container leaked | script bug | grep -cv … \|\| true; pre-flight cleanup of leftovers | sandbox-run.sh v0.1/v0.2 |
| 4 | 15 Jul | exec | Permission denied on first write: host cloned as root, agent runs as uid 1001 across mount boundary | script bug (mount/uid) | chown -R 1001:1001 after clone; safe.directory for root-side harvest | sandbox-run.sh v0.2 |
| 5 | 15 Jul | harvest | Agent telemetry (.claude-output.json/.claude-stderr.log) landed inside the repo diff. Escalated 17 Jul: a real dependency install put .venv/ (1201 files) in the diff too — harvest became meaningless and would poison any PR push | design (escape hatch too wide) | **RESOLVED 18 Jul (v0.4).** Root insight: the bind mount is a deliberate escape hatch from an ephemeral container; the bug was its width. Three destinations now — code changes → mounted repo; agent report → separate /workspace/out mount; venv/caches → UNMOUNTED paths that die with the container. Harvest excludes as safety net. Verified: changed_files 1201 → 0 | sandbox-run.sh v0.4 |
| 6 | 16 Jul | deploy (Langfuse) | ClickHouse crash-looped: "max_memory_usage appeared at top level" — user-profile setting, invalid in server config.d | config error | Removed max_memory_usage; kept only max_server_memory_usage | clickhouse-memory.xml |
| 7 | 16 Jul | deploy (Langfuse) | langfuse-web P1000 DB auth — DATABASE_URL fell back to upstream default password 'postgres' | config gap (template drift) | Added explicit DATABASE_URL to .env.example; aligned template to upstream compose vars | langfuse/.env.example |
| 8 | 16 Jul | deploy (Langfuse) | Postgres volume initialized during earlier partial boot with a mismatched password; correct .env still failed | state (init-once) | down + docker volume rm langfuse_langfuse_postgres_data + up | deploy-langfuse.md gotchas |
| 9 | 17 Jul | deploy (gateway) | tinyproxy filter sed with \\. escapes did not match; api.anthropic.com line survived first removal attempt | ops (regex escaping) | Simpler literal sed '/anthropic/d'; verified grep -c = 0 (verify, don't assume) | tinyproxy-filter |
| 10 | 19 Jul | placement (Keel v0.1) | Command block assumed repo at ~/waterline; real clone is ~/projects/waterline. mkdir -p created the stray tree instead of failing, so five files landed in a directory that looked correct from the shell. Surfaced six exchanges later via "not a git repository". Compounded: a partial keel/ already existed in the real repo, so the corrective mv nested it as keel/keel/ | process (unverified assumption) | Flattened nesting, moved into real repo, removed stray, committed. Protocol amendment: command blocks that write to a path must use a path confirmed in-session, or open with a step that fails loudly. Do not infer repo locations | this log; working protocol |
| 11 | 20 Jul | deploy (Keel v0.1.1 upgrade) | Pasted command block died at a `quote>` prompt: an apostrophe in a comment label line opened an unterminated zsh string and swallowed every following line; separately, pasted `#` labels error as commands because interactive_comments is off in this zsh | ops (shell quoting) | Ctrl+C, re-ran block with ASCII-clean label; protocol: label lines carry no apostrophes or parentheses; optional permanent fix `setopt interactive_comments` | working protocol |

| 12 | 20 Jul | config (Keel settings) | `Write(/**)` deny — intended as "deny all absolute-path writes" — was an invalid pattern that Claude Code SILENTLY IGNORED: no error, no warning, no protection, for five runs. Surfaced only because probe target-keel-05 ordered the agent to attempt the forbidden write and it succeeded. Compounding: silence also fit "flag bypasses denies", a wrong diagnosis that stood for half a day | config (silent-ignore of invalid rule) | Corrected to `//**` (absolute form). Verified by three probes: interactive Write denied with no prompt; sandbox Write denied; sandbox Bash redirect to the denied path also denied and recorded in permission_denials. Rule going forward: a deny is not deployed until a probe has watched it refuse | keel/settings.json v0.1.2; README v0.1.3 two-walls; this log |


Diagnosis discipline (from the harness article): name the layer first —
harness/infra failures (permissions, network, credentials, config) vs loop
failures (agent never converges, verification passes garbage). Entries 1–12
are all infra/script/config/ops/process layer; no agent-behavior failures yet.

Recurring shape — **silent success where an error was warranted.** Five
instances: an invalid deny pattern silently discarded while appearing to
protect (12); `mkdir -p` fabricating a wrong path rather than failing (10); a
direct edit to a managed Keel file overwritten with no warning on upgrade
(SSOT drift, docs/deferred.md); an unset KEEL_TEST_CMD disabling the
done-means-verified gate while merely nagging (require-green.sh); an npm
install whose postinstall never ran, leaving a stub that failed only weeks
later (environment, 20 Jul). Entry 3 is the inverse — a loud failure on a
correct state. The design rule falling out of this: when a step encodes an
assumption, make its violation noisy; when a config claims protection, probe
it before trusting it. Convenience that suppresses errors is how an assumption
survives long enough to compound — and a protection you have only read is a
protection you do not have.