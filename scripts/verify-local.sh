#!/usr/bin/env bash
# verify-local.sh — re-run every port's test suite against its LOCAL directory.
# Fast: no clone, no rebuild from scratch. Use during dev.
#
# Usage:
#   ./scripts/verify-local.sh            # all 23 ports
#   ./scripts/verify-local.sh agent-id   # just one (matches -py and -rs)
#
# Output: per-port PASS/FAIL line + final summary table.
# Exit: 0 if all green, 1 if anything red, 2 if something is missing.

set -uo pipefail

PERSONAL="${PERSONAL_DIR:-/Users/vladbordei/Documents/Development/PERSONAL}"

# All 12 base repo names. agent-rooms only has -rs (no -py port).
REPOS=(
  agent-id agent-cid agent-scroll agent-rerun agent-toolprint
  agent-launch agent-publish agent-fleet agent-ask agent-phone agent-pay
)
ROOMS_RS_ONLY=(agent-rooms)

FILTER="${1:-}"

# Color codes
G='\033[32m'; R='\033[31m'; Y='\033[33m'; N='\033[0m'

declare -a RESULTS=()  # "<repo>|<lang>|<status>|<count>|<detail>"

run_py() {
  local repo="$1"
  local dir="$PERSONAL/$repo-py"
  if [ ! -d "$dir" ]; then
    RESULTS+=("$repo|py|MISSING||no directory")
    printf "${Y}MISS${N} %-22s py\n" "$repo"
    return
  fi
  if [ ! -d "$dir/.venv" ]; then
    (cd "$dir" && uv venv -p 3.13 -q && uv pip install -q -e ".[dev]") >/dev/null 2>&1 || {
      RESULTS+=("$repo|py|SETUP_FAIL||uv venv/install failed")
      printf "${R}SETUP${N} %-22s py — uv install failed\n" "$repo"
      return
    }
  fi
  local out
  out=$(cd "$dir" && uv run pytest -q 2>&1 | tail -3)
  if echo "$out" | grep -qE '[0-9]+ passed' && ! echo "$out" | grep -qE 'failed|error'; then
    local n=$(echo "$out" | grep -oE '[0-9]+ passed' | head -1 | grep -oE '[0-9]+')
    RESULTS+=("$repo|py|PASS|$n|all passed")
    printf "${G}PASS${N} %-22s py — %s passed\n" "$repo" "$n"
  else
    RESULTS+=("$repo|py|FAIL||$(echo "$out" | tr '\n' ' ' | head -c 80)")
    printf "${R}FAIL${N} %-22s py\n" "$repo"
    echo "$out" | sed 's/^/    /'
  fi
}

run_rs() {
  local repo="$1"
  local dir="$PERSONAL/$repo-rs"
  if [ ! -d "$dir" ]; then
    RESULTS+=("$repo|rs|MISSING||no directory")
    printf "${Y}MISS${N} %-22s rs\n" "$repo"
    return
  fi
  local out
  out=$(cd "$dir" && cargo test --quiet 2>&1)
  local fail_count=$(echo "$out" | grep -cE 'test result: FAILED|FAILED \(')
  local results=$(echo "$out" | grep -E 'test result: ok' | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' | awk '{s+=$1} END {print s+0}')
  if [ "$fail_count" -eq 0 ] && [ "${results:-0}" -gt 0 ]; then
    RESULTS+=("$repo|rs|PASS|$results|all passed")
    printf "${G}PASS${N} %-22s rs — %s passed\n" "$repo" "$results"
  else
    RESULTS+=("$repo|rs|FAIL|$results|$fail_count failures")
    printf "${R}FAIL${N} %-22s rs — %s failures\n" "$repo" "$fail_count"
    echo "$out" | tail -15 | sed 's/^/    /'
  fi
}

ALL=("${REPOS[@]}" "${ROOMS_RS_ONLY[@]}")
if [ -n "$FILTER" ]; then
  ALL=()
  for r in "${REPOS[@]}" "${ROOMS_RS_ONLY[@]}"; do
    [[ "$r" == *"$FILTER"* ]] && ALL+=("$r")
  done
fi

echo "Verifying ${#ALL[@]} ports against local directories..."
echo ""
for r in "${ALL[@]}"; do
  # rooms only has -rs
  if [[ " ${ROOMS_RS_ONLY[*]} " == *" $r "* ]]; then
    run_rs "$r"
  else
    run_py "$r"
    run_rs "$r"
  fi
done

echo ""
echo "=== Summary ==="
printf "%-22s  %-4s  %-6s  %s\n" "REPO" "LANG" "STATUS" "DETAIL"
printf "%-22s  %-4s  %-6s  %s\n" "----" "----" "------" "------"
fails=0
for line in "${RESULTS[@]}"; do
  IFS='|' read -r repo lang status count detail <<< "$line"
  [[ "$status" != "PASS" ]] && fails=$((fails+1))
  printf "%-22s  %-4s  %-6s  %s\n" "$repo" "$lang" "$status" "${count:+$count tests; }$detail"
done
echo ""
total=${#RESULTS[@]}
passed=$((total - fails))
echo "${passed}/${total} green."

if [ "$fails" -gt 0 ]; then
  exit 1
fi
exit 0
