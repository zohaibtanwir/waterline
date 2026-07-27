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
| 12 | 20 Jul | config (Keel settings) | `Write(/**)` deny — intended as "deny all absolute-path writes" — was an invalid pattern that Claude Code SILENTLY IGNORED: no error, no warning, no protection, for five runs. Surfaced only because probe target-keel-05 ordered the agent to attempt the forbidden write and it succeeded. Compounding: silence also fit "flag bypasses denies", a wrong diagnosis that stood for half a day | config (silent-ignore of invalid rule) | Corrected to `//**` (absolute form). **Verification claim revised 26 Jul.** The interactive Door-1 probe stands. The two sandbox probes do NOT — see #13 for the attribution error (those refusals came from the image's managed-settings.json, not from Keel) and #14 for the field (permission_denials returns empty while denials sit in the stream). What Keel's deny actually does was settled later, on target-tc-04's stream: it blocks the Edit and Write tools and nothing else, and the agent routed around it with `cat >` and then `python3` to the identical path, in the same turn, twice. Rule going forward unchanged, with an addition: a deny is not deployed until a probe has watched it refuse — and the probe must watch the RIGHT LAYER refuse | keel/settings.json v0.1.2; README v0.1.3 two-walls; this log |
| 13 | 22 Jul | verification (L3 evidence base) | Claude Code ignored `.claude/settings.json` in EVERY sandbox run to date — `"Ignoring 10 permissions.allow entries from .claude/settings.json: this workspace has not been trusted"` sat in the stderr of all seven runs, unread after run 02. Keel's allow-list, deny-list and hook registration therefore did nothing. Probe target-keel-06's refusals — published as proof that Keel's denies bind headlessly — actually came from the image's `managed-settings.json`, which needs no trust. Surfaced only when the first L4 run (target-tc-01) failed and its stderr was read line by line | process (verified the outcome, not the mechanism) | Documents corrected before any new run: architecture.md L3 section re-marked claim-by-claim with evidence, exit gate 2 restated as NOT MET AS STATED, Keel README to v0.1.4. Image fix pending: set `hasTrustDialogAccepted` for the workspace path in the agent's `.claude.json` so repo-level settings load at all; then re-probe Keel's own denies and the gate's registration path. **Closed 26 Jul:** sandbox-base:v2 bakes the trust flag, and target-tc-05's keel-gate.log proves the Stop hook registers from Keel's own settings.json — the hook is declared nowhere else | docs/architecture.md; keel/README.md v0.1.4; images/sandbox-base v2; this log |
| 14 | 24-26 Jul | harvest (the result record) | Four fields in the harness result record read as authoritative and were not. `permission_denials` returned `[]` on target-tc-04 while four "denied by your permission settings" results sat in that same run's stream. `num_turns` reported 1 for target-tc-05, a 2493-second run whose stream holds 70 assistant messages — it had also reported 1 for an earlier 20-minute run and 3 correctly for a short one, so it breaks on long runs specifically. `settings_loaded` is computed by grepping stderr for the trust warning, so it has only ever meant "no warning found"; on a fast failure with empty stderr it reports true. `model_usage.costUSD` is the CLI's fallback price table applied to gateway aliases it cannot resolve — verified by reconstruction on two runs at $5/M in, $25/M out, 0.1x cache read, 1.25x cache write, applied IDENTICALLY to `execute` and to `claude-opus-4-8`, which is the giveaway; it was wrong by 1.10x on tc-04 and 1.90x on tc-05 against the gateway ledger, and the ledger matched the Console credit delta exactly on both runs | verification (the record used to judge every run) | v0.12 takes both counts from the stream — `turns_from_stream`, `denials_from_stream` — renames `settings_loaded` to `trust_warning_absent` and `costUSD` to `costUSD_cli_estimate`, and adds `gate_firings` after tc-05's gate fired twice with the record silent about it. `num_turns` is retained alongside `turns_from_stream` deliberately, so the CLI bug stays visible rather than being quietly papered over | bin/sandbox-run.sh v0.12; this log |
| 15 | 26 Jul | exec (agent behaviour) | target-tc-05 spent about 31% of its budget after both suites were already green and the Stop gate had already passed. Arithmetic from three artifacts: `keel-gate.log` gives the first pass at 07:37:37Z; `gateway-spend-timeline.jsonl` reads 3.683296 at 07:37:47; final `spend_usd` was 5.371443; the difference is $1.688147 of $5.371443. Mechanism, from the agent's own messages in the stream: it ran the suites as BACKGROUND tasks, and their completions woke it back up after it had finished, whereupon it re-confirmed the same green result — "The second agents-suite run also completed with exit code 0", then "All three independent runs confirmed. Nothing further to act on." `keel-gate.log` carries two firings, 07:37:37 and 07:54:19, seventeen minutes apart | loop (agent never converges on done) — the FIRST agent-behaviour entry in this log; 1-14 are all infra/script/config/ops/process/verification | Keel v0.3 adds to CONVENTIONS.md: run the test command once, in the foreground; do not run it in the background, because a background result arrives after you have moved on and pulls you back into work you had already completed; once a suite has passed do not run it again for confidence, because the Stop gate runs the same command itself before the work is accepted. EFFECT UNMEASURED — target-tc-06 is the A/B that tests it | keel/CONVENTIONS.md v0.3; this log |
| 16 | 27 Jul | harvest (script bug, caught pre-run) | sandbox-run.sh v0.12 guarded its three new stream counters with `\|\| echo 0`. `grep -c` prints its count and exits 1 when that count is zero, so the command substitution captured grep's "0" followed by echo's "0" — two lines. `jq ... \| tonumber` fails on that, jq exits non-zero, and under `set -euo pipefail` the script dies before writing the result record. Destroy runs before the record is built (v0.11), so the run would have completed, spent its money, revoked its key, and produced no result at all. The trigger condition is the SUCCESS case: `denials_from_stream` is zero on every run since Keel v0.2 removed `Edit(//**)` | script bug (guard that guarded wrong) | v0.12.1: `\|\| true` emits nothing where `\|\| echo 0` emitted a second line, plus an empty check on each counter. Confirmed by simulating the harvest path against a zero-denial stream before deploying. Caught by reading the code before the run, not by the run failing | bin/sandbox-run.sh v0.12.1; this log |
| 17 | 27 Jul | exec (external quota) | target-tc-06's first attempt died at 112 seconds having spent $0.93, with a 400: "You have reached your specified workspace API usage limits. You will regain access on 2026-08-01 at 00:00 UTC." This is the Anthropic WORKSPACE monthly spend limit — $15.00, set by us, hit at $15.32. It sits upstream of the LiteLLM gateway, so neither `caps.budget_usd` nor the v0.11 ledger kill poller could see or prevent it. Until this point the design assumed two budget layers; there are three, and the outermost was the only one not written down anywhere | infra (external quota, undocumented layer) | Limit raised to $50, restoring the correct nesting: workspace 50 > gateway 20 > ledger kill 15. Each layer must stay looser than the one inside it, or the least reliable counter decides the outcome. Added to the pre-run checklist: verify workspace headroom before spending | session-context spend posture; docs/change-log.md; this log |

---

Diagnosis discipline (from the harness article): name the layer first —
harness/infra failures (permissions, network, credentials, config) vs loop
failures (agent never converges, verification passes garbage). Entries 1–14 are
infra, script, config, ops, process and verification layer. Entry 15 is the
first loop-layer failure recorded here — an agent that reached a correct,
gated, verified result and then spent a third of the run failing to believe it.
Worth naming what it is not: not a wrong answer, not a weakened test, not a
fake done. Every check the harness makes passed. The waste was invisible to all
of them, and surfaced only because the spend timeline and the gate log could be
read against each other.

Recurring shape — **silent success where an error was warranted.** Eight
instances: an untrusted settings file ignored with a warning nobody read, for
seven consecutive runs (13); an invalid deny pattern silently discarded while
appearing to protect (12); `permission_denials` reporting an empty list while
four denials sat in the same run's stream (14); `mkdir -p` fabricating a wrong
path rather than failing (10); a direct edit to a managed Keel file overwritten
with no warning on upgrade (SSOT drift, docs/deferred.md); an unset
KEEL_TEST_CMD disabling the done-means-verified gate while merely nagging
(require-green.sh); an npm install whose postinstall never ran, leaving a stub
that failed weeks later; and corepack resolving a pinned pnpm version forward
while the build stayed green (fixed same day by asserting versions instead of
printing them). Entry 3 is the inverse — a loud failure on a correct state. 
** The count goes from eight to nine —
add entry 16, a guard whose failure path emitted a value that looked like the
value it was guarding against.

Entry 14 is worth reading as three more of the same shape if you want the count
higher: `num_turns` returning 1, `settings_loaded` meaning something narrower
than it says, and `costUSD` presenting a guess in the same shape as a fact. They
are counted here as one entry because they were found and fixed together, but
each is independently the pattern.

Entry 13 adds a second rule to the first. The original: when a step encodes an
assumption, make its violation noisy; a protection you have only read is a
protection you do not have. The addition: **verifying an outcome is not
verifying a mechanism.** Probes 05 and 06 correctly established that a write
was refused — and were wrong about what refused it. When a control is layered,
a passing probe identifies only that *some* layer held. Name the layer, or the
claim is unearned. Every "verified" in this substrate's documents should carry
the artifact that proves it; where it cannot, the word is "unverified" and that
is an acceptable thing for a document to say.

Entry 15 adds a third. The first two are about not trusting a control you have
not watched work. This one is about the opposite failure: a control that DID
work, whose result was not trusted. The gate passed, and the agent kept
re-verifying anyway. A harness that only catches under-verification will not
see over-verification at all — it costs budget, produces no signal, and every
check reports success while it happens.
