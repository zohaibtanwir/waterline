# Deferred

Things we noticed, understood well enough to build, and deliberately did not
build yet.

Day zero should be simple. Architecture evolves from observation, not from
anticipation. This file is the other half of that discipline: deferral only
works if the note is good enough to act on cold, months later, without
re-deriving the reasoning.

Every entry carries three things: **what** we saw, **why** it matters, and the
**trigger** that says it is time. An item with no trigger is a wish, not a
deferral.

Filed by layer of origin, not by the layer that will build it.

---

## From L2 — gateway

### (a) Eval-informed routing
**What.** L2 routes by an explicit `tier` field in the task spec: plan →
frontier, execute → mid, verify → Haiku. Dumb, declarative, legible. Systems
like TensorZero learn routing from observed outcomes instead.
**Why.** Declarative routing is a guess made once at task-authoring time. A
learned router uses what actually happened — cost, latency, whether the task
passed — to route the next one.
**Trigger.** Enough completed tasks in Langfuse to constitute a training signal
(order of hundreds, not tens), and a measured gap between what the tier field
chose and what would have been optimal.

### (b) gVisor runtime
**What.** The sandbox runs on plain Docker. The runtime slot was designed to
accept gVisor; it is not enabled.
**Why.** Container escape is the residual risk in the sandbox model. gVisor
narrows it substantially. It is also the answer to a specific question in
regulated-client security reviews.
**Trigger.** First engagement with a client whose security review asks how we
isolate untrusted agent execution — likely insurance or healthcare.

### (d) Full economics dashboard
**What.** Per-task cost is captured in the gateway spend ledger and traces land
in Langfuse. There is no dashboard over them.
**Why.** Cost per task is the number that makes or breaks the commercial
argument. Right now it takes a manual look to answer "what did this cost."
**Trigger.** L8. Or earlier, if a client asks for cost reporting as a
deliverable.

### (d-i) Model name missing from traces
**What.** LiteLLM's Langfuse integration does not surface the model name in the
trace. Cost is captured; which model spent it is not.
**Why.** Without it, tier-routing cannot be verified from telemetry — you can
see spend but not what it bought. This gap is what forced an inference earlier
in the build (an agent's model choice was asserted from cost, not observed).
**Trigger.** Any work on tier-routing verification. Blocking for L3 item #3.

### (e) Gateway swap — Bifrost / Portkey
**What.** LiteLLM is the gateway. The design treats it as swappable.
**Why.** Some regulated clients will have opinions about the gateway, or will
already run one. The swap should be a config change, not a rebuild.
**Trigger.** A client who already has a gateway, or one who rejects LiteLLM on
review.

### (f) Fleet scaling — bootstrap-runner.sh
**What.** Runner #1 was built by hand on purpose; the manual steps are the
spec. `provision-runner.sh` exists (level 1). A self-configuring bootstrap
(fetch keys over tailnet, clone, build, deploy) does not (level 2). Runners as
cattle, spawned by a control plane, is level 3.
**Why.** One runner is a lab. The substrate story requires that runner #2 costs
minutes, not an afternoon.
**Trigger.** Level 2 when a second runner is genuinely needed — parallel task
execution, or a second target repo under active work. Level 3 is L6+.

### (g) Tighter key model — runner asks controller to mint
**What.** The LiteLLM master key lives on the runner host so it can mint
per-task virtual keys. The tighter model: the runner requests a key from the
controller, and the master key never leaves the controller.
**Why.** Master key on the runner means a runner compromise is a mint
capability. Acceptable for a two-box lab; not for a fleet.
**Trigger.** Build alongside (f) level 2 — the moment runners become numerous
or disposable, master-key-per-runner stops being defensible.

### (h) Secrets management
**What.** The real Anthropic key and the gateway master key sit in plaintext
`.env` files (0600, tailnet-only). Flagged as interim since L0.
**Why.** It works and it is honestly scoped, but it is the first thing a client
security review will find. Upgrade path: sops/age at minimum (encrypted
values, git-safe), Vault or a cloud secrets manager ideally — LiteLLM supports
Vault-backed keys with runtime fetch, rotation, and audit.
**Trigger.** First client security review. Or first time a secret needs
rotating, whichever comes first.

### (i) Per-sandbox identity — mTLS
**What.** Gateway access is authenticated by the master key and reachable only
on the tailnet. There is no per-sandbox cryptographic identity.
**Why.** Today the gateway enforces a per-task budget because the runner minted
a per-task key. With mTLS or a signed token, the gateway could enforce it
against a verified identity rather than trusting the key handoff.
**Trigger.** Alongside (g). Same threshold: fleet, not lab.

---

## From L3 — harness

### The loop runner
**What.** Keel defines the floor; the loop runs on top of it. The standalone
Plan→Act→Verify runner — fresh context each iteration, state on disk in a goal
spec plus an implementation plan updated in place — is not built. Deferred by
explicit call, 19 Jul. Reference shape when the time comes:
ghuntley/how-to-ralph-wiggum (smallest), with the caveat that waterline's
`sandbox-run.sh` already plays part of this role for the unattended case; the
missing piece is iteration — today a task gets one shot, not a converge loop.
**Why.** Without a runner the harness is rules with no iteration. With one, a
task that fails the gate retries against disk state instead of ending.
**Trigger.** After Keel v0.1 is verified live on target-flaskapp. Or the first
task that needs convergence rather than a single pass.
**Status 20 Jul (L3 close).** Trigger FIRED — six verified runs, every Keel
mechanism probed on both doors. Held by explicit choice, and deliberately
assigned to NO layer: L3 closed as the harness layer without it, and it does
not enter L4 or any other layer until its adoption and placement have been
debated on their own. The three design forks from the 20 Jul discussion
(state in the out-mount vs repo; loop outside sandbox-run.sh as composition;
convergence = the loop runs KEEL_TEST_CMD itself, never the agent's
self-declared STATUS) are recorded here so the debate starts warm, not cold.

### Async spend ledger on fast runs
**What.** The gateway spend query at task destroy under-reports on short
runs: a 7s probe read $0.0022 against ~$0.18 of token cost; a 13s probe read
$0.096 against ~$0.197. LiteLLM updates its spend ledger asynchronously, and
the runner queries it immediately before revoking the key.
**Why.** The result record's spend_usd is the number we quote. On fast tasks
it can be wrong by an order of magnitude. model_usage (v0.6) carries the
agent-side figure as a cross-check, but agent-side pricing is unreliable with
gateway aliases — so neither number alone is trustworthy on a fast run.
**Trigger.** sandbox-run v0.7: delay or retry the spend query before revoke.
Or the economics layer (L8), whichever comes first.

### Path-scoped rules
**What.** `.claude/rules/*.md` are discovered recursively. Rules carrying a
`paths` frontmatter field load only when the agent touches matching files;
rules without it load at launch at CLAUDE.md priority. Progressive disclosure
applied to conventions rather than skills.
**Why.** Keel's `CONVENTIONS.md` is imported, and imports load at launch — the
whole file is charged to every session whether or not its rules apply. Path
scoping would make situational rules (security rules for `auth/`, migration
rules for `db/`) free until relevant.
**Not now because.** Path globs are repo facts, which puts them in the local
layer, and we do not yet know which of our rules are situational. We would be
guessing at the split.
**Trigger.** First target where `CONVENTIONS.md` exceeds ~40 lines.
**Related finding.** Only *nested* CLAUDE.md files load lazily. Module-level
repo facts are therefore free until touched; imported base conventions are not.
This asymmetry should shape where things live.

### Human gate on repeated failure
**What.** When the Stop hook's test gate fails twice, pause and require human
intervention before work resumes — rather than letting the agent finish with a
loud complaint. Mechanism: the hook writes a blocker file (`.keel-blocked`) on
second failure; a SessionStart hook refuses to proceed while it exists; a human
reads the reason and deletes it to unblock.
**Why.** Same shape as Chachamaru127's non-bypassable Bootstrap Gate, which was
built for a reason worth taking seriously: LLMs rationalise past soft warnings.
So, at 6pm, do people.
**Not now because.** It needs an unblock path, and a story for the unattended
case — in waterline the sandbox is destroyed at task end, so there is no human
to pause for and no file to survive. The feature has no user in the environment
we are currently building.
**Trigger.** First engagement where a human developer is interactively in the
loop — the client-terminal case rather than waterline's unattended runner. Or
a single observed instance of someone starting a fresh session on top of a red
state.
**Constraint found.** Stop hooks have no exit code that halts and hands control
to a person. Exit 2 makes the agent continue; exit 0 lets it finish. Any human
gate must be file-plus-SessionStart, not an exit code.

### Should an unconfigured Keel refuse rather than nag?
**What.** If `KEEL_TEST_CMD` is unset, the Stop gate exits 0 with a loud stderr
warning naming the missing variable. The done-means-verified gate is off.
**Why it is open.** Loud is the v0.1 decision and it is defensible — an
unconfigured install is annoying rather than invisible. But it is exactly the
soft warning that the item above says gets rationalised past. A repo where
someone forgot to set the variable has a Keel that permits fake-done forever
and merely complains about it.
**Trigger.** Evidence from a real install. If the nag gets ignored once, make
it refuse.

### SSOT drift — direct edits to managed files
**What.** Keel ships files into a client repo that look editable but are not.
An engineer edits `.claude/keel/settings.json`, commits, and loses the change
silently on the next Keel upgrade. No error, no conflict, no warning.
**Why.** This is not hypothetical. Chachamaru127/claude-code-harness hit the
same shape five separate times in a single-author codebase — their name for it
is 片肺 sync, "one-lung sync": a downstream config edited without updating the
`harness.toml` SSOT, silently overwritten on the next sync. If it recurs five
times where one person controls everything, it will recur in a client repo we
do not own. And there the cost is trust in the substrate, not one config line.
**Their fix, three parts.** Drift warning at edit time; SSOT alignment test;
CI gate that fails the build on mismatch.
**Minimum for us.** The warning. v0.1 ships a managed-file header comment in
every base file, which is a marker with nothing yet reading it — enough to make
the boundary legible to a human, not enough to catch a machine.
**Trigger.** Before the second client install. One target can be managed by
convention; two cannot.

---

## Cross-cutting

### Session durability
**What.** Waterline sandboxes are one-shot. A task runs, the container dies,
the conversation dies with it. There is no session layer.
**Why.** Three independent sources converged on this being the missing piece.
Shopify's Aquifer separates a durable Session (a Postgres event log) from a
disposable Harness and a disposable Sandbox — and states the split cannot be
retrofitted. claude-mem exists entirely to solve it for single developers.
And the "how do learnings from my session reach the rest of the team" question
is the same gap approached from the org side.
**Trigger.** L6 conversational dispatch, or the first request for a multi-turn
task. Design it before building it — the retrofit warning is explicit.

### Central learning capture
**What.** A developer teaches the agent something during a session. Today that
knowledge dies at session end. The ask: capture it before compaction or exit,
store it centrally, and inject it as context for every developer's next
session.
**Why.** This is the compounding mechanism for an org-wide substrate. Without
it, four hundred engineers each teach the same lesson four hundred times.
**Where it connects.** Mechanically it is the session-durability item above.
Governance-wise it is the promotion test in Keel's README — not everything
learned should be promoted, and the filter matters more than the pipe.
**Trigger.** After the first multi-developer engagement produces a concrete
example of a lesson worth propagating. Build the filter before the pipe.

### Outer development loop
**What.** A cluster of items from the same conversation: PR artifact standards
(e.g. require a screenshot for UI changes before agent review), third-party
review agents (CodeRabbit, Greptile), CI gates, headless browser testing
agents, read-only DB access, mail agents.
**Why.** All real, all valuable, none of them harness concerns. They are the
substrate *around* the agent rather than the floor beneath it.
**Trigger.** L5/L6. Sort individually when the harness is proven on a target.

### Environment standardisation
**What.** OS standardisation, package manager and tool installation, app-run
procedures — consistent across squads.
**Why.** Partly solved already: the sandbox image pins Claude Code and bakes
its own environment. The unsolved part is the developer's own machine, which
is where most of the variance lives.
**Related.** Nix is the rigorous answer to this class of problem — explicit
dependency graphs, content-addressed immutable builds, sandboxed builds that
cannot see what they did not declare. Our pinned image and iptables lockdown
are the crude version of the same principle.
**Trigger.** L4 reproducibility work, or the first "works on my machine"
failure that costs a day.

### Org-evolution research pass (the twenty-item list)
**What.** His standing list of org-scale practices: cloning and standardising
skills across squads, package-manager and OS standardisation, app-run skills,
code-search optimisation, root-vs-module CLAUDE.md structure, CI gates and
pre/post hooks, central learning capture at session end, central
context-injection at session start, LLM conventions, prompt optimisation,
setup/run scripts, env secrets discipline, PR artifact standards, PR review
agents (CodeRabbit, Greptile), coding conventions, testing discipline,
security checks, controlling non-determinism, model routing
("ministry of experts"), read-only DB access, headless browser testing
agents, mail agents. Three items already absorbed into Keel v0.1 (ripgrep
rule, secrets never-do, module-CLAUDE.md finding).
**Why.** This is the substrate's org-scale evolution — the difference between
a harness that works and a practice that compounds across four hundred
engineers. Deliberately not day-zero: researching twenty practices against an
unproven harness would have produced guesses.
**Output when run.** Per-item best-practice position plus a layer assignment:
absorb into Keel / L5 / L6 / defer-with-trigger.
**Trigger.** L3 closed and the first multi-developer or client-repo
engagement in view — the pass needs a real org to aim at.

### Harder proving grounds
**What.** target-flaskapp is 110 lines with one real bug. Trip Concierge is a
genuine application.
**Why.** A harness proven on a toy proves little. But a harness debugged on a
complex target confounds harness problems with target problems — which is why
the toy went first.
**Trigger.** After target-flaskapp's make-tests-pass task runs clean end to end.

### Test economics — cassettes and local models
**What.** Every harness test run costs real money at frontier prices. Recorded
cassettes for deterministic replay, or a local model for loop-shape tests,
would decouple iteration speed from spend.
**Why.** The $0.34 read-and-report baseline is fine once. It is not fine as the
unit cost of debugging a loop.
**Trigger.** L4, or the first week where test spend becomes noticeable.

---

## How to use this file

When an item's trigger fires, it graduates: move it out of here, into the
change log as work done, and into `docs/architecture.md` if it changed the
shape of the system.

When a trigger will clearly never fire, delete the entry. A register that only
grows is as useless as no register at all — the same rule as Keel's promotion
test, applied to our own notes.
