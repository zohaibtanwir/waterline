#!/usr/bin/env bash
# waterline sandbox runner v0.12.1 — mint → inject → exec → harvest → destroy
# v0.12.1 FIXES A BUG SHIPPED IN v0.12, found before it ran.
#   The three new counters were guarded with `|| echo 0`. `grep -c` prints its
#   count AND exits 1 when the count is zero, so on a zero count the command
#   substitution captured grep's "0" and then echo's "0" — two lines. jq's
#   tonumber then fails on "0\n0", jq exits non-zero, and under `set -euo
#   pipefail` the script dies BEFORE writing the result record. Destroy has
#   already run by that point, so the run would have completed, spent its money,
#   and produced no result record at all.
#   It would have fired on the SUCCESS case specifically: denials_from_stream is
#   zero whenever the deny rules do not trigger, which is every run since Keel
#   v0.2. Guards are now `|| true` (which emits nothing) plus an empty check.
#
# New in v0.12 — the result record stops lying. Every change here is HARVEST-TIME
# only: nothing the agent sees or does is altered, so a run under v0.12 is still
# comparable to one under v0.11.
#   Four fields in the v0.11 record read as authoritative and were not. Each is the
#   silent-success shape the failure log keeps catching — a confident wrong answer
#   where an error or an honest blank was warranted — sitting inside the very record
#   used to judge runs.
#   - turns_from_stream: counts "type":"assistant" lines in the stream. num_turns is
#     KEPT alongside it, deliberately, so the CLI bug stays visible instead of being
#     quietly papered over. On target-tc-05 num_turns reported 1 for a 2493-second
#     run whose stream holds 70 assistant messages. It was also 1 on an earlier
#     20-minute run and correct (3) on a short one, so it breaks on long runs.
#   - denials_from_stream: counts "denied by your permission settings" in the stream.
#     The agent report's permission_denials came back [] on target-tc-04 while four
#     denials sat in that run's stream. The stream is the artifact; the report is not.
#   - trust_warning_absent: renamed from settings_loaded. No logic change. The value
#     is computed by grepping stderr for the trust warning, so it has only ever meant
#     "no warning found" — on a fast failure with empty stderr it reports true, which
#     is not the same claim as "settings confirmed loaded".
#   - costUSD_cli_estimate: renamed inside model_usage. The CLI cannot price a gateway
#     alias like "execute", so it applies a fallback table — verified by reconstruction
#     on two runs at $5/M in, $25/M out, 0.1x cache read, 1.25x cache write, applied
#     IDENTICALLY to execute and to claude-opus-4-8, which is the giveaway. Its error
#     grows with cache-creation volume: 1.10x wrong on tc-04, 1.90x on tc-05.
#     spend_usd is the gateway ledger and is the real number — it matched the Console
#     credit delta exactly on both runs. The token counts in model_usage are real and
#     are retained; only the cost figure was renamed.
#   - gate_firings: counts lines in keel-gate.log. On target-tc-05 the gate fired
#     TWICE (07:37:37 and 07:54:19) and the record said nothing, so the fact that the
#     agent tried to stop, was let go, and then worked for another seventeen minutes
#     was invisible until the log was read by hand.
# v0.11 (retained):
#   - LEDGER KILL POLLER. A background loop samples /key/info every 30s, appends
#     {ts, spend} to gateway-spend-timeline.jsonl, and tears the container down if the
#     LEDGER spend crosses caps.kill_usd.
#     Why: target-tc-04 died on "429 Budget has been exceeded! Current cost: 5.0,
#     Max budget: 5.0" while its own result record said spend_usd 2.448. /spend/logs
#     later agreed with 2.448 to nine decimal places, as did the Console delta.
#     Nothing in the ledger ever reached 5.0, so the gateway's ENFORCEMENT counter and
#     its LEDGER are two different numbers and only the ledger has ever been right.
#     NOTE the ledger is asynchronous, so the kill LAGS and will overshoot kill_usd by
#     whatever the lag costs. Set kill_usd below the number you cannot exceed, and set
#     caps.budget_usd — the gateway's own cap, and the unreliable one — above it, so
#     the broken counter is not what stops the run.
#     caps.kill_usd absent or 0 disables the kill; the timeline is still written.
#   - Gateway spend audit: the /key/info response is SAVED rather than scraped and
#     discarded (gateway-key-info.json), and the per-request ledger rows are captured
#     alongside it (gateway-spend-logs.json), both while the virtual key still exists.
#     Written RAW, no jq in the pipe, so a 404 or schema change lands in the file
#     where it can be read instead of being swallowed into a null.
#   - Verified revocation: the key/delete response is captured and the key is then
#     RE-QUERIED to confirm it no longer resolves. Result: key_revoked. The old line
#     ended in `>/dev/null 2>&1 || true` — a failed revocation printed the same
#     success message as a good one and left a budget-capped key live for its full
#     hour. Verified by OUTCOME, not by trusting the response body.
#   - Destroy runs BEFORE the result record is built so key_revoked can be recorded.
# v0.10 (retained): turn-stream capture. The agent runs with --output-format
#   stream-json --verbose to claude-stream.jsonl. claude-output.json is derived from
#   the LAST "type":"result" line, deliberately NOT `tail -1` — on a run killed by the
#   host timeout the CLI never writes its result line, and tail would grab a
#   mid-stream object that is valid JSON and parses to nulls.
# v0.9 (retained): trust preflight (failure-log #13) and the stderr trust check.
# v0.8 (retained): image is a task-spec field and is recorded.
# v0.7 (retained): num_turns lifted from the report; spend query hardened against the
#   async gateway ledger.
# v0.6 (retained): modelUsage lifted into model + model_usage.
# v0.5 (retained): task-spec "env" injected as container environment variables.
# v0.4 (retained): out-mount for report; unmounted venv/caches; harvest excludes;
#   "mount":"ro"|"rw"; result record with report_path + summary.
# Usage: sandbox-run.sh <task-spec.json>
set -euo pipefail
export GIT_TERMINAL_PROMPT=0

TASK_FILE="${1:?Usage: sandbox-run.sh <task-spec.json>}"
TASK_ID=$(jq -r .task_id "$TASK_FILE")
REPO_URL=$(jq -r .repo_url "$TASK_FILE")
BRANCH=$(jq -r '.branch // "main"' "$TASK_FILE")
PROMPT=$(jq -r .prompt "$TASK_FILE")
TIMEOUT_S=$(jq -r '.caps.timeout_seconds // 900' "$TASK_FILE")
MEM=$(jq -r '.caps.memory // "2g"' "$TASK_FILE")
CPUS=$(jq -r '.caps.cpus // "2"' "$TASK_FILE")
BUDGET=$(jq -r '.caps.budget_usd // 1' "$TASK_FILE")
KILL_USD=$(jq -r '.caps.kill_usd // 0' "$TASK_FILE")
MOUNT_MODE=$(jq -r '.mount // "rw"' "$TASK_FILE")   # "ro" for analyze-only tasks
IMAGE=$(jq -r '.image // "waterline/sandbox-base:v1"' "$TASK_FILE")

# v0.5: per-task env from spec → docker -e flags
ENV_FLAGS=()
while IFS= read -r kv; do
  [ -n "$kv" ] && ENV_FLAGS+=(-e "$kv")
done < <(jq -r '.env // {} | to_entries[] | "\(.key)=\(.value)"' "$TASK_FILE")

# v0.9: refuse to run on an image that has not marked the workspace trusted
TRUST_OK=$(docker run --rm "$IMAGE" bash -lc \
  'node -e "try{const c=require(\"/home/agent/.claude.json\");console.log(c.projects[\"/workspace/repo\"].hasTrustDialogAccepted===true?\"yes\":\"no\")}catch(e){console.log(\"no\")}"' 2>/dev/null || echo no)
if [ "$TRUST_OK" != "yes" ]; then
  echo "FATAL: $IMAGE does not mark /workspace/repo as trusted." >&2
  echo "Claude Code would ignore the repo's .claude/settings.json and the" >&2
  echo "harness would silently do nothing. Rebuild the image (see failure-log #13)." >&2
  exit 3
fi

GATEWAY_URL="http://100.98.245.52:4000"
GATEWAY_MASTER_KEY=$(cat /opt/waterline/gateway-master.key)

WORK=/opt/waterline/sandboxes/$TASK_ID
OUT=$WORK/out
RESULT=/opt/waterline/results/$TASK_ID.json
CN=sbx-$TASK_ID

# pre-flight: clear leftovers from any prior run of this task id
docker rm -f "$CN" >/dev/null 2>&1 || true
rm -rf "$WORK"
mkdir -p "$WORK" "$OUT"

echo "[$TASK_ID] mint: per-task virtual key (gateway cap \$$BUDGET, ledger kill \$$KILL_USD)"
VKEY=$(curl -s -X POST "$GATEWAY_URL/key/generate" \
  -H "Authorization: Bearer $GATEWAY_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"key_alias\":\"$TASK_ID\",\"max_budget\":$BUDGET,\"duration\":\"1h\"}" \
  | jq -r .key)
if [ -z "$VKEY" ] || [ "$VKEY" = "null" ]; then
  echo "[$TASK_ID] FATAL: gateway did not return a virtual key"; exit 2
fi

echo "[$TASK_ID] inject: cloning $REPO_URL ($BRANCH) [mount: $MOUNT_MODE]"
git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$WORK/repo"
BASE_SHA=$(git -C "$WORK/repo" rev-parse HEAD)
chown -R 1001:1001 "$WORK/repo" "$OUT"

REPO_MOUNT="$WORK/repo:/workspace/repo"
[ "$MOUNT_MODE" = "ro" ] && REPO_MOUNT="$REPO_MOUNT:ro"

# v0.11: ledger poller. Samples the number that has always been right, records a
# timeline, and kills the container if it crosses kill_usd. Started BEFORE the
# container so sampling covers the whole run.
TIMELINE="$OUT/gateway-spend-timeline.jsonl"
: > "$TIMELINE"
(
  while true; do
    sleep 30
    TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    RESP=$(curl -s -m 10 -X GET "$GATEWAY_URL/key/info?key=$VKEY" \
      -H "Authorization: Bearer $GATEWAY_MASTER_KEY" 2>/dev/null || echo '{}')
    S=$(printf '%s' "$RESP" | jq -r '.info.spend // 0' 2>/dev/null || echo 0)
    case "$S" in ''|null) S=0 ;; esac
    printf '{"ts":"%s","spend":%s}\n' "$TS" "$S" >> "$TIMELINE"
    if [ "$KILL_USD" != "0" ] && awk -v s="$S" -v k="$KILL_USD" 'BEGIN{exit !(s>=k)}'; then
      echo "[$TASK_ID] KILL: ledger spend $S crossed kill threshold $KILL_USD" >&2
      printf '{"ts":"%s","event":"kill","spend":%s,"kill_usd":%s}\n' \
        "$TS" "$S" "$KILL_USD" >> "$TIMELINE"
      docker rm -f "$CN" >/dev/null 2>&1 || true
      break
    fi
  done
) &
POLLER_PID=$!

echo "[$TASK_ID] create+exec: $IMAGE (timeout ${TIMEOUT_S}s, mem $MEM, cpus $CPUS, extra env: $(( ${#ENV_FLAGS[@]} / 2 )))"
START=$(date -u +%s)
set +e
timeout "${TIMEOUT_S}s" docker run --name "$CN" \
  --network sandbox-net --memory "$MEM" --cpus "$CPUS" \
  -e ANTHROPIC_API_KEY="$VKEY" \
  -e ANTHROPIC_BASE_URL="$GATEWAY_URL" \
  -e TASK_PROMPT="$PROMPT" \
  -e PIP_CACHE_DIR=/tmp/pip-cache \
  ${ENV_FLAGS[@]+"${ENV_FLAGS[@]}"} \
  -v "$REPO_MOUNT" \
  -v "$OUT:/workspace/out" \
  "$IMAGE" \
  bash -lc "cd /workspace/repo && claude -p \"\$TASK_PROMPT\" --output-format stream-json --verbose --dangerously-skip-permissions > /workspace/out/claude-stream.jsonl 2>/workspace/out/claude-stderr.log" \
  2>"$WORK/docker.log"
EXIT=$?
set -e
END=$(date -u +%s)

# v0.11: stop the poller
kill "$POLLER_PID" >/dev/null 2>&1 || true
wait "$POLLER_PID" 2>/dev/null || true

KILLED_BY_POLLER=false
if grep -q '"event":"kill"' "$TIMELINE" 2>/dev/null; then
  KILLED_BY_POLLER=true
  echo "[$TASK_ID] NOTE: run was terminated by the ledger kill poller" >&2
fi

echo "[$TASK_ID] harvest"

# v0.10: derive the summary record from the last result line of the stream.
# NOT tail -1 — see the header note on host-timeout kills.
STREAM_PATH="$OUT/claude-stream.jsonl"
REPORT_PATH="$OUT/claude-output.json"
if [ -f "$STREAM_PATH" ]; then
  STREAM_LINES=$(wc -l < "$STREAM_PATH" | tr -d ' ')
  grep '"type":"result"' "$STREAM_PATH" 2>/dev/null | tail -1 > "$REPORT_PATH" || true
  if [ ! -s "$REPORT_PATH" ]; then
    echo "[$TASK_ID] WARNING: stream has $STREAM_LINES lines but no result record" >&2
    echo "[$TASK_ID]          (expected if the run was killed by the timeout or the poller)" >&2
  fi
else
  echo "[$TASK_ID] WARNING: no turn stream was written" >&2
fi

# v0.12: counts taken from the STREAM, which is the artifact, rather than from the
# agent's own report, which has been wrong on both of these.
TURNS_FROM_STREAM=0
DENIALS_FROM_STREAM=0
if [ -f "$STREAM_PATH" ]; then
  TURNS_FROM_STREAM=$(grep -c '"type":"assistant"' "$STREAM_PATH" 2>/dev/null || true)
  DENIALS_FROM_STREAM=$(grep -c "denied by your permission settings" "$STREAM_PATH" 2>/dev/null || true)
fi
[ -z "$TURNS_FROM_STREAM" ] && TURNS_FROM_STREAM=0
[ -z "$DENIALS_FROM_STREAM" ] && DENIALS_FROM_STREAM=0

# v0.12: the gate audits every firing to this log. Counting the lines shows whether
# the agent tried to stop more than once.
GATE_LOG="$OUT/keel-gate.log"
GATE_FIRINGS=0
if [ -f "$GATE_LOG" ]; then
  GATE_FIRINGS=$(grep -c . "$GATE_LOG" 2>/dev/null || true)
fi
[ -z "$GATE_FIRINGS" ] && GATE_FIRINGS=0

DIFF_FILE="$WORK/changes.diff"
git config --global --add safe.directory "$WORK/repo" >/dev/null 2>&1 || true
# safety-net excludes: junk that should have died with the container
cat > "$WORK/.harvest-excludes" << 'EOF'
.venv/
venv/
node_modules/
__pycache__/
*.pyc
.claude-output.json
.claude-stderr.log
.pytest_cache/
EOF
git -C "$WORK/repo" add -A
while read -r pat; do
  git -C "$WORK/repo" reset -q -- "$pat" 2>/dev/null || true
  git -C "$WORK/repo" rm -r -q --cached --ignore-unmatch "$pat" 2>/dev/null || true
done < "$WORK/.harvest-excludes"
git -C "$WORK/repo" diff --cached "$BASE_SHA" > "$DIFF_FILE" || true
CHANGED=$(git -C "$WORK/repo" diff --cached --name-only "$BASE_SHA" | wc -l | tr -d ' ')

# agent report: path + short summary
# v0.12: costUSD inside model_usage is renamed to costUSD_cli_estimate. The CLI
# cannot price a gateway alias, so that figure is a fallback-table guess; spend_usd
# is the ledger and is the real number. Token counts are kept as-is — they are real.
SUMMARY=""
MODEL="unknown"
MODEL_USAGE="{}"
NUM_TURNS=0
if [ -s "$REPORT_PATH" ]; then
  SUMMARY=$(jq -r '.result // empty' "$REPORT_PATH" 2>/dev/null | head -c 200 || true)
  MODEL=$(jq -r '.modelUsage | keys[0] // "unknown"' "$REPORT_PATH" 2>/dev/null || echo unknown)
  MODEL_USAGE=$(jq -c '.modelUsage // {} | with_entries(.value |= (if type == "object" and has("costUSD") then (. + {costUSD_cli_estimate: .costUSD} | del(.costUSD)) else . end))' "$REPORT_PATH" 2>/dev/null || echo '{}')
  [ -z "$MODEL_USAGE" ] && MODEL_USAGE='{}'
  NUM_TURNS=$(jq -r '.num_turns // 0' "$REPORT_PATH" 2>/dev/null || echo 0)
fi

# v0.9 logic, v0.12 name: this greps stderr for the trust warning, so it means
# "no warning found", NOT "settings confirmed loaded". Renamed to say so.
TRUST_WARNING_ABSENT=true
if grep -q "has not been trusted" "$OUT/claude-stderr.log" 2>/dev/null; then
  TRUST_WARNING_ABSENT=false
  echo "[$TASK_ID] WARNING: repo settings were IGNORED (workspace not trusted)" >&2
fi

# v0.7: the spend ledger is asynchronous — wait, then poll while it reads zero
# v0.11: keep the response instead of scraping and discarding it
KEY_INFO_PATH="$OUT/gateway-key-info.json"
SPEND_LOGS_PATH="$OUT/gateway-spend-logs.json"
DELETE_PATH="$OUT/gateway-key-delete.json"
sleep 10
SPEND=0
for _try in 1 2 3 4; do
  curl -s -X GET "$GATEWAY_URL/key/info?key=$VKEY" \
    -H "Authorization: Bearer $GATEWAY_MASTER_KEY" > "$KEY_INFO_PATH" 2>/dev/null || true
  SPEND=$(jq -r '.info.spend // 0' "$KEY_INFO_PATH" 2>/dev/null || echo 0)
  [ "$SPEND" != "0" ] && [ "$SPEND" != "null" ] && break
  sleep 5
done

# v0.11: per-request ledger rows, captured while the key still exists.
curl -s -X GET "$GATEWAY_URL/spend/logs?api_key=$VKEY" \
  -H "Authorization: Bearer $GATEWAY_MASTER_KEY" > "$SPEND_LOGS_PATH" 2>/dev/null || true
if [ ! -s "$SPEND_LOGS_PATH" ]; then
  echo "[$TASK_ID] WARNING: gateway returned no spend-log rows for this key" >&2
fi

# v0.11: destroy moved ahead of the result record so revocation can be recorded
echo "[$TASK_ID] destroy: container + revoke virtual key"
docker rm -f "$CN" >/dev/null 2>&1 || true
curl -s -X POST "$GATEWAY_URL/key/delete" \
  -H "Authorization: Bearer $GATEWAY_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"keys\":[\"$VKEY\"]}" > "$DELETE_PATH" 2>/dev/null || true

# Verify by OUTCOME, not by trusting the delete response body: a revoked key
# no longer resolves.
KEY_REVOKED=true
if curl -s -X GET "$GATEWAY_URL/key/info?key=$VKEY" \
     -H "Authorization: Bearer $GATEWAY_MASTER_KEY" 2>/dev/null \
   | jq -e '.info.spend' >/dev/null 2>&1; then
  KEY_REVOKED=false
  echo "[$TASK_ID] WARNING: virtual key STILL RESOLVES after delete." >&2
  echo "[$TASK_ID]          It stays live until its 1h expiry. Revoke by hand." >&2
fi

STATUS=completed
[ $EXIT -eq 124 ] && STATUS=timeout
[ $EXIT -ne 0 ] && [ $EXIT -ne 124 ] && STATUS=failed
[ "$KILLED_BY_POLLER" = "true" ] && STATUS=killed_budget

jq -n \
  --arg task_id "$TASK_ID" \
  --arg status "$STATUS" \
  --arg exit_code "$EXIT" \
  --arg base_sha "$BASE_SHA" \
  --arg duration "$((END-START))" \
  --arg changed_files "$CHANGED" \
  --arg spend "$SPEND" \
  --arg budget "$BUDGET" \
  --arg kill_usd "$KILL_USD" \
  --argjson killed_by_poller "$KILLED_BY_POLLER" \
  --arg mount "$MOUNT_MODE" \
  --arg image "$IMAGE" \
  --argjson trust_warning_absent "$TRUST_WARNING_ABSENT" \
  --argjson key_revoked "$KEY_REVOKED" \
  --arg model "$MODEL" \
  --arg num_turns "$NUM_TURNS" \
  --arg turns_from_stream "$TURNS_FROM_STREAM" \
  --arg denials_from_stream "$DENIALS_FROM_STREAM" \
  --arg gate_firings "$GATE_FIRINGS" \
  --argjson model_usage "$MODEL_USAGE" \
  --arg diff_path "$DIFF_FILE" \
  --arg report_path "$REPORT_PATH" \
  --arg stream_path "$STREAM_PATH" \
  --arg key_info_path "$KEY_INFO_PATH" \
  --arg spend_logs_path "$SPEND_LOGS_PATH" \
  --arg timeline_path "$TIMELINE" \
  --arg summary "$SUMMARY" \
  --arg workdir "$WORK" \
  '{task_id:$task_id, status:$status, exit_code:($exit_code|tonumber),
    base_sha:$base_sha, duration_seconds:($duration|tonumber),
    changed_files:($changed_files|tonumber),
    spend_usd:($spend|tonumber), budget_usd:($budget|tonumber),
    kill_usd:($kill_usd|tonumber), killed_by_poller:$killed_by_poller,
    mount:$mount, image:$image, trust_warning_absent:$trust_warning_absent,
    key_revoked:$key_revoked, model:$model, model_usage:$model_usage,
    num_turns:($num_turns|tonumber),
    turns_from_stream:($turns_from_stream|tonumber),
    denials_from_stream:($denials_from_stream|tonumber),
    gate_firings:($gate_firings|tonumber),
    diff_path:$diff_path,
    report_path:$report_path, stream_path:$stream_path,
    key_info_path:$key_info_path, spend_logs_path:$spend_logs_path,
    timeline_path:$timeline_path,
    summary:$summary, workdir:$workdir}' \
  > "$RESULT"

echo "[$TASK_ID] result:"
cat "$RESULT"
