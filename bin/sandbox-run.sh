#!/usr/bin/env bash
# waterline sandbox runner v0.3 — create → inject → exec → harvest → destroy
# New in v0.3: per-task virtual key minted from the LiteLLM gateway (budget-capped),
# injected instead of a real Anthropic key, revoked at destroy. Sandbox holds no
# real credential. Model traffic goes gateway-direct (ANTHROPIC_BASE_URL -> gateway).
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
BUDGET=$(jq -r '.caps.budget_usd // 1' "$TASK_FILE")   # per-task $ cap; default $1

# Gateway coordinates (host-only config; NOT baked into the image)
GATEWAY_URL="http://100.98.245.52:4000"
GATEWAY_MASTER_KEY=$(cat /opt/waterline/gateway-master.key)   # 0600, host only

WORK=/opt/waterline/sandboxes/$TASK_ID
RESULT=/opt/waterline/results/$TASK_ID.json
CN=sbx-$TASK_ID

# pre-flight: clear leftovers from any prior run of this task id
docker rm -f "$CN" >/dev/null 2>&1 || true
rm -rf "$WORK"
mkdir -p "$WORK"

echo "[$TASK_ID] mint: per-task virtual key (budget \$$BUDGET)"
VKEY=$(curl -s -X POST "$GATEWAY_URL/key/generate" \
  -H "Authorization: Bearer $GATEWAY_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"key_alias\":\"$TASK_ID\",\"max_budget\":$BUDGET,\"duration\":\"1h\"}" \
  | jq -r .key)
if [ -z "$VKEY" ] || [ "$VKEY" = "null" ]; then
  echo "[$TASK_ID] FATAL: gateway did not return a virtual key"; exit 2
fi

echo "[$TASK_ID] inject: cloning $REPO_URL ($BRANCH)"
git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$WORK/repo"
BASE_SHA=$(git -C "$WORK/repo" rev-parse HEAD)
chown -R 1001:1001 "$WORK/repo"

echo "[$TASK_ID] create+exec: sandbox up (timeout ${TIMEOUT_S}s, mem $MEM, cpus $CPUS)"
START=$(date -u +%s)
set +e
timeout "${TIMEOUT_S}s" docker run --name "$CN" \
  --network sandbox-net --memory "$MEM" --cpus "$CPUS" \
  -e ANTHROPIC_API_KEY="$VKEY" \
  -e ANTHROPIC_BASE_URL="$GATEWAY_URL" \
  -e TASK_PROMPT="$PROMPT" \
  -v "$WORK/repo:/workspace/repo" \
  waterline/sandbox-base:v0 \
  bash -lc "cd /workspace/repo && claude -p \"\$TASK_PROMPT\" --output-format json --dangerously-skip-permissions > /workspace/repo/.claude-output.json 2>/workspace/repo/.claude-stderr.log" \
  2>"$WORK/docker.log"
EXIT=$?
set -e
END=$(date -u +%s)

echo "[$TASK_ID] harvest"
DIFF_FILE="$WORK/changes.diff"
git config --global --add safe.directory "$WORK/repo" >/dev/null 2>&1 || true
git -C "$WORK/repo" add -A
git -C "$WORK/repo" diff --cached "$BASE_SHA" > "$DIFF_FILE" || true
CHANGED=$(git -C "$WORK/repo" diff --cached --name-only "$BASE_SHA" | grep -cv '^\.claude-' || true)

# per-task spend, read back from the gateway before we revoke the key
SPEND=$(curl -s -X GET "$GATEWAY_URL/key/info?key=$VKEY" \
  -H "Authorization: Bearer $GATEWAY_MASTER_KEY" | jq -r '.info.spend // 0' 2>/dev/null || echo 0)

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
  --arg diff_path "$DIFF_FILE" \
  --arg workdir "$WORK" \
  '{task_id:$task_id, status:$status, exit_code:($exit_code|tonumber),
    base_sha:$base_sha, duration_seconds:($duration|tonumber),
    changed_files:($changed_files|tonumber),
    spend_usd:($spend|tonumber), budget_usd:($budget|tonumber),
    diff_path:$diff_path, workdir:$workdir}' \
  > "$RESULT"

echo "[$TASK_ID] destroy: container + revoke virtual key"
docker rm -f "$CN" >/dev/null 2>&1 || true
curl -s -X POST "$GATEWAY_URL/key/delete" \
  -H "Authorization: Bearer $GATEWAY_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"keys\":[\"$VKEY\"]}" >/dev/null 2>&1 || true

echo "[$TASK_ID] result:"
cat "$RESULT"
