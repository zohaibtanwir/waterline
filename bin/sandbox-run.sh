#!/usr/bin/env bash
# waterline sandbox runner v0.10 — mint → inject → exec → harvest → destroy
# New in v0.10:
#   - Turn-stream capture. The agent now runs with --output-format stream-json
#     --verbose, writing one JSON object per line to /workspace/out/
#     claude-stream.jsonl: every tool call with its arguments, every result,
#     and a leading system/init line listing the tools available at launch.
#     The summary record we have always harvested is the LAST line of that
#     stream, so claude-output.json is derived from it and every downstream
#     parse is unchanged.
#     Why: the result record answers "what did this run cost and did it
#     change anything". It cannot answer "which files did the agent open,
#     what did it re-derive, how many times did it run the tests" — the
#     questions the L4 exploration autopsy is made of. It also could not
#     settle target-tc-03, where permission_denials was empty while the agent
#     narrated a refusal: with the stream, either an Edit tool call is in the
#     record or it is not.
#     Derivation is deliberately NOT `tail -1`. On a run killed by the host
#     timeout the CLI never writes its result line, and tail would grab a
#     mid-stream object that is valid JSON and parses to nulls — a silent
#     wrong answer where today we get a caught failure. Selecting the last
#     line of type "result" yields an empty file instead, so the existing
#     `// empty` / `// "unknown"` guards fire exactly as they do now.
#   - stream_path in the result record.
# v0.9 (retained):
#   - Trust preflight: asserts the image marks /workspace/repo as trusted
#     before spending anything. Without trust Claude Code silently ignores the
#     repo's .claude/settings.json — which disabled Keel in every run up to
#     22 Jul (failure-log #13). A run on an untrusted image is a run whose
#     harness does nothing, so it must not start.
#   - Harvest greps the agent's stderr for the trust warning and records
#     settings_loaded in the result record. Belt and braces: the preflight can
#     pass and the warning can still appear if the mount path ever changes.
#     NOTE the field is computed by absence of a warning, so it means "no
#     warning found", not "settings confirmed loaded" — on a fast failure with
#     empty stderr it reports true.
# v0.8 (retained):
#   - Image is a task-spec field ("image", default sandbox-base:v1) and is
#     recorded in the result record. The image is an experiment variable now
#     that it carries project toolchains (uv, pnpm), so a run must say which
#     one it used rather than leaving it implicit in this script.
# v0.7 (retained):
#   - num_turns lifted from the agent report into the result record (the turn
#     count is the context-cost multiplier; needed for exploration autopsies).
#   - Spend query hardened against the async gateway ledger: wait, then poll
#     briefly while the ledger still reads zero. Reduces (does not eliminate)
#     under-reporting on short runs; model_usage remains the cross-check.
# v0.6 (retained):
#   - Harvest lifts modelUsage from the agent report into the result record:
#     "model" (first model key, e.g. an alias like "execute" or a concrete
#     model name) and "model_usage" (the full per-model token/cost object).
#     Gateway spend remains the authoritative cost; model_usage is evidence.
#   - "extra env" log line now counts variables, not array elements.
# v0.5 (retained):
#   - Task-spec "env": {"KEY":"value", ...} — injected into the container as
#     environment variables. Transport for per-task config that must reach the
#     agent session and its hooks (e.g. KEEL_TEST_CMD) without editing managed
#     files in the target repo. Keys are passed as-is; values must not contain
#     secrets (per-task model key is injected separately by this script).
# v0.4 (retained): out-mount for report; unmounted venv/caches; harvest
#   excludes; "mount":"ro"|"rw"; result record with report_path + summary.
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

echo "[$TASK_ID] mint: per-task virtual key (budget \$$BUDGET)"
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
    echo "[$TASK_ID]          (expected if the run was killed by the timeout)" >&2
  fi
else
  echo "[$TASK_ID] WARNING: no turn stream was written" >&2
fi

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
SUMMARY=""
MODEL="unknown"
MODEL_USAGE="{}"
NUM_TURNS=0
if [ -s "$REPORT_PATH" ]; then
  SUMMARY=$(jq -r '.result // empty' "$REPORT_PATH" 2>/dev/null | head -c 200 || true)
  MODEL=$(jq -r '.modelUsage | keys[0] // "unknown"' "$REPORT_PATH" 2>/dev/null || echo unknown)
  MODEL_USAGE=$(jq -c '.modelUsage // {}' "$REPORT_PATH" 2>/dev/null || echo '{}')
  NUM_TURNS=$(jq -r '.num_turns // 0' "$REPORT_PATH" 2>/dev/null || echo 0)
fi

# v0.9: did Claude Code actually load the repo's settings this run?
SETTINGS_LOADED=true
if grep -q "has not been trusted" "$OUT/claude-stderr.log" 2>/dev/null; then
  SETTINGS_LOADED=false
  echo "[$TASK_ID] WARNING: repo settings were IGNORED (workspace not trusted)" >&2
fi

# v0.7: the spend ledger is asynchronous — wait, then poll while it reads zero
sleep 10
SPEND=0
for _try in 1 2 3 4; do
  SPEND=$(curl -s -X GET "$GATEWAY_URL/key/info?key=$VKEY" \
    -H "Authorization: Bearer $GATEWAY_MASTER_KEY" | jq -r '.info.spend // 0' 2>/dev/null || echo 0)
  [ "$SPEND" != "0" ] && [ "$SPEND" != "null" ] && break
  sleep 5
done

STATUS=completed
[ $EXIT -eq 124 ] && STATUS=timeout
[ $EXIT -ne 0 ] && [ $EXIT -ne 124 ] && STATUS=failed

jq -n \
  --arg task_id "$TASK_ID" \
  --arg status "$STATUS" \
  --arg exit_code "$EXIT" \
  --arg base_sha "$BASE_SHA" \
  --arg duration "$((END-START))" \
  --arg changed_files "$CHANGED" \
  --arg spend "$SPEND" \
  --arg budget "$BUDGET" \
  --arg mount "$MOUNT_MODE" \
  --arg image "$IMAGE" \
  --argjson settings_loaded "$SETTINGS_LOADED" \
  --arg model "$MODEL" \
  --arg num_turns "$NUM_TURNS" \
  --argjson model_usage "$MODEL_USAGE" \
  --arg diff_path "$DIFF_FILE" \
  --arg report_path "$REPORT_PATH" \
  --arg stream_path "$STREAM_PATH" \
  --arg summary "$SUMMARY" \
  --arg workdir "$WORK" \
  '{task_id:$task_id, status:$status, exit_code:($exit_code|tonumber),
    base_sha:$base_sha, duration_seconds:($duration|tonumber),
    changed_files:($changed_files|tonumber),
    spend_usd:($spend|tonumber), budget_usd:($budget|tonumber),
    mount:$mount, image:$image, settings_loaded:$settings_loaded, model:$model, model_usage:$model_usage,
    num_turns:($num_turns|tonumber),
    diff_path:$diff_path,
    report_path:$report_path, stream_path:$stream_path, summary:$summary, workdir:$workdir}' \
  > "$RESULT"

echo "[$TASK_ID] destroy: container + revoke virtual key"
docker rm -f "$CN" >/dev/null 2>&1 || true
curl -s -X POST "$GATEWAY_URL/key/delete" \
  -H "Authorization: Bearer $GATEWAY_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"keys\":[\"$VKEY\"]}" >/dev/null 2>&1 || true

echo "[$TASK_ID] result:"
cat "$RESULT"
