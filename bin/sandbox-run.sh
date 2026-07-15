#!/usr/bin/env bash
# waterline sandbox runner v0.2 — create → inject → exec → harvest → destroy
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

WORK=/opt/waterline/sandboxes/$TASK_ID
RESULT=/opt/waterline/results/$TASK_ID.json
CN=sbx-$TASK_ID

# pre-flight: clear leftovers from any prior run of this task id
docker rm -f "$CN" >/dev/null 2>&1 || true
rm -rf "$WORK"
mkdir -p "$WORK"

echo "[$TASK_ID] inject: cloning $REPO_URL ($BRANCH)"
git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$WORK/repo"
BASE_SHA=$(git -C "$WORK/repo" rev-parse HEAD)
chown -R 1001:1001 "$WORK/repo"   # match the sandbox 'agent' uid

echo "[$TASK_ID] create+exec: sandbox up (timeout ${TIMEOUT_S}s, mem $MEM, cpus $CPUS)"
START=$(date -u +%s)
set +e
timeout "${TIMEOUT_S}s" docker run --name "$CN" \
  --network sandbox-net --memory "$MEM" --cpus "$CPUS" \
  --env-file /opt/waterline/task.env -e TASK_PROMPT="$PROMPT" \
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
  --arg diff_path "$DIFF_FILE" \
  --arg workdir "$WORK" \
  '{task_id:$task_id, status:$status, exit_code:($exit_code|tonumber),
    base_sha:$base_sha, duration_seconds:($duration|tonumber),
    changed_files:($changed_files|tonumber), diff_path:$diff_path, workdir:$workdir}' \
  > "$RESULT"

echo "[$TASK_ID] destroy"
docker rm -f "$CN" >/dev/null 2>&1 || true

echo "[$TASK_ID] result:"
cat "$RESULT"
