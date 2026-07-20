#!/usr/bin/env bash
# KEEL v0.1.2 — managed file. Do not edit here.
# Context budget check (run from the target repo root, or pass the root as $1).
#
# Counts the assembled standing context an agent session pays for at launch:
# CLAUDE.md plus every file it imports with an @path line. Warns past the soft
# limit, fails past the hard limit. Evidence for the limits: oversized standing
# context measurably degrades task completion (arXiv 2606.10209: 91.6% -> 71%).
#
# Exit codes: 0 within budget, 1 over hard limit, 2 usage error.
set -uo pipefail

ROOT="${1:-.}"
SOFT=250
HARD=300
CLAUDE_MD="$ROOT/CLAUDE.md"

if [ ! -f "$CLAUDE_MD" ]; then
  echo "keel-budget: no CLAUDE.md at $ROOT" >&2
  exit 2
fi

total=0
report=""

count_file() {
  local f="$1" label="$2" n
  n=$(wc -l < "$f" | tr -d ' ')
  total=$((total + n))
  report="${report}  ${n}\t${label}\n"
}

count_file "$CLAUDE_MD" "CLAUDE.md"

# @imports: lines beginning with @, path relative to repo root
while IFS= read -r imp; do
  path="${imp#@}"
  if [ -f "$ROOT/$path" ]; then
    count_file "$ROOT/$path" "$path (import)"
  else
    echo "keel-budget: WARNING import not found: $path" >&2
  fi
done < <(grep -E '^@[^ ]+' "$CLAUDE_MD" | sed 's/[[:space:]].*$//')

printf "assembled standing context:\n"
printf "%b" "$report"
printf "  %s\ttotal (soft %s, hard %s)\n" "$total" "$SOFT" "$HARD"

if [ "$total" -gt "$HARD" ]; then
  echo "keel-budget: OVER HARD LIMIT — prune before adding anything." >&2
  exit 1
elif [ "$total" -gt "$SOFT" ]; then
  echo "keel-budget: over soft limit — additions now need to displace something." >&2
fi
exit 0
