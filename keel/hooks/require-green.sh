#!/usr/bin/env bash
# KEEL v0.1.2 — managed file. Do not edit here.
# Repo-specific config goes in .claude/settings.local.json (KEEL_TEST_CMD).
#
# Stop hook. Exit 2 refuses the agent's finish and feeds stderr back to it.
# Exit 0 lets the turn end. Exit 1 does NOT block — never use it here.
# v0.1.1: every branch appends an audit line to /workspace/out/keel-gate.log
# (when that mount exists) so gate activity is externally observable in the
# harvest, independent of what the agent chooses to report.
set -uo pipefail

audit() {
  [ -d /workspace/out ] && echo "$(date -u +%FT%TZ) $*" >> /workspace/out/keel-gate.log
  return 0
}

payload=$(cat)

# Second pass through: the gate already fired once and the agent tried again.
# Let the turn end rather than looping forever, but end it loudly.
if printf '%s' "$payload" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
  audit "branch=second-pass result=released-unverified"
  echo "KEEL: tests still failing after a retry. Ending turn UNVERIFIED." >&2
  echo "KEEL: treat this task as NOT done. See the report." >&2
  exit 0
fi

if [ -z "${KEEL_TEST_CMD:-}" ]; then
  audit "branch=unset result=gate-off"
  echo "KEEL: KEEL_TEST_CMD is not set — the done-means-verified gate is OFF." >&2
  echo "KEEL: set it in .claude/settings.local.json to enable verification." >&2
  exit 0
fi

if output=$(eval "$KEEL_TEST_CMD" 2>&1); then
  audit "branch=green result=pass test_exit=0"
  exit 0
else
  test_exit=$?
fi

audit "branch=red result=refused test_exit=$test_exit"
{
  echo "KEEL: the test suite is red. You are not done."
  echo "KEEL: fix the cause. Do not weaken, skip, or delete tests."
  echo "--- ${KEEL_TEST_CMD} ---"
  printf '%s\n' "$output" | tail -40
} >&2
exit 2
