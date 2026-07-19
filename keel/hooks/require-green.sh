#!/usr/bin/env bash
# KEEL v0.1 — managed file. Do not edit here.
# Repo-specific config goes in .claude/settings.local.json (KEEL_TEST_CMD).
#
# Stop hook. Exit 2 refuses the agent's finish and feeds stderr back to it.
# Exit 0 lets the turn end. Exit 1 does NOT block — never use it here.
set -uo pipefail

payload=$(cat)

# Second pass through: the gate already fired once and the agent tried again.
# Let the turn end rather than looping forever, but end it loudly.
if printf '%s' "$payload" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
  echo "KEEL: tests still failing after a retry. Ending turn UNVERIFIED." >&2
  echo "KEEL: treat this task as NOT done. See the report." >&2
  exit 0
fi

if [ -z "${KEEL_TEST_CMD:-}" ]; then
  echo "KEEL: KEEL_TEST_CMD is not set — the done-means-verified gate is OFF." >&2
  echo "KEEL: set it in .claude/settings.local.json to enable verification." >&2
  exit 0
fi

if output=$(eval "$KEEL_TEST_CMD" 2>&1); then
  exit 0
fi

{
  echo "KEEL: the test suite is red. You are not done."
  echo "KEEL: fix the cause. Do not weaken, skip, or delete tests."
  echo "--- ${KEEL_TEST_CMD} ---"
  printf '%s\n' "$output" | tail -40
} >&2
exit 2
