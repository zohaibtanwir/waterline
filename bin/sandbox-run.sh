#!/usr/bin/env bash
# waterline sandbox runner v0.4 — mint → inject → exec → harvest → destroy
# New in v0.4 (the "escape hatch is too wide" fix):
#   - Second mount /workspace/out for agent report (survives, cleanly separated)
#   - Agent stdout/stderr go to /workspace/out, NOT into the repo
#   - venv/caches directed to UNMOUNTED paths (/workspace/venv, /tmp) — die with container
#   - Harvest ignore patterns as safety net (.venv, node_modules, __pycache__, .claude-*)
#   - Result record gains report_path + summary
#   - Task-spec field "mount": "ro"|"rw" (default rw) — read-only enforced for analyze tasks
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

echo "[$TASK_ID] create+exec: sandbox up (timeout ${TIMEOUT_S}s, mem $MEM, cpus $CPUS)"
START=$(date -u +%s)
set +e
timeout "${TIMEOUT_S}s" docker run --name "$CN" \
  --network sandbox-net --memory "$MEM" --cpus "$CPUS" \
  -e ANTHROPIC_API_KEY="$VKEY" \
  -e ANTHROPIC_BASE_URL="$GATEWAY_URL" \
  -e TASK_PROMPT="$PROMPT" \
  -e PIP_CACHE_DIR=/tmp/pip-cache \
  -v "$REPO_MOUNT" \
  -v "$OUT:/workspace/out" \
  waterline/sandbox-base:v0 \
  bash -lc "cd /workspace/repo && claude -p \"\$TASK_PROMPT\" --output-format json --dangerously-skip-permissions > /workspace/out/claude-output.json 2>/workspace/out/claude-stderr.log" \
  2>"$WORK/docker.log"
EXIT=$?
set -e
END=$(date -u +%s)

echo "[$TASK_ID] harvest"
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
# unstage excluded patterns (safety net — this junk should have died with the container)
while read -r pat; do
  git -C "$WORK/repo" reset -q -- "$pat" 2>/dev/null || true
  git -C "$WORK/repo" rm -r -q --cached --ignore-unmatch "$pat" 2>/dev/null || true
done < "$WORK/.harvest-excludes"
git -C "$WORK/repo" diff --cached "$BASE_SHA" > "$DIFF_FILE" || true
CHANGED=$(git -C "$WORK/repo" diff --cached --name-only "$BASE_SHA" | wc -l | tr -d ' ')

# agent report: path + short summary
REPORT_PATH="$OUT/claude-output.json"
SUMMARY=""
if [ -f "$REPORT_PATH" ]; then
  SUMMARY=$(jq -r '.result // empty' "$REPORT_PATH" 2>/dev/null | head -c 200 || true)
fi

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
  --arg mount "$MOUNT_MODE" \
  --arg diff_path "$DIFF_FILE" \
  --arg report_path "$REPORT_PATH" \
  --arg summary "$SUMMARY" \
  --arg workdir "$WORK" \
  '{task_id:$task_id, status:$status, exit_code:($exit_code|tonumber),
    base_sha:$base_sha, duration_seconds:($duration|tonumber),
    changed_files:($changed_files|tonumber),
    spend_usd:($spend|tonumber), budget_usd:($budget|tonumber),
    mount:$mount, diff_path:$diff_path,
    report_path:$report_path, summary:$summary, workdir:$workdir}' \
  > "$RESULT"

echo "[$TASK_ID] destroy: container + revoke virtual key"
docker rm -f "$CN" >/dev/null 2>&1 || true
curl -s -X POST "$GATEWAY_URL/key/delete" \
  -H "Authorization: Bearer $GATEWAY_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"keys\":[\"$VKEY\"]}" >/dev/null 2>&1 || true

echo "[$TASK_ID] result:"
cat "$RESULT"
