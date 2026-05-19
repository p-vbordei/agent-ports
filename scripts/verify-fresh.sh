#!/usr/bin/env bash
# verify-fresh.sh — clone each port from GitHub into a temp dir and run its tests.
# Authoritative: confirms what's actually on the remote works for a new user.
# Slow: full clone + install + build for 23 repos. Expect 10-15 min.
#
# Usage:
#   ./scripts/verify-fresh.sh             # all 23 ports
#   ./scripts/verify-fresh.sh agent-id    # just one base name
#   ./scripts/verify-fresh.sh --keep      # don't delete temp dirs (debugging)
#
# Output: per-port PASS/FAIL + final summary. Logs at $TMP/<repo>.log.
# Exit: 0 if all green, 1 if anything red.

set -uo pipefail

REPOS=(
  agent-id agent-cid agent-scroll agent-rerun agent-toolprint
  agent-launch agent-publish agent-fleet agent-ask agent-phone agent-pay
)
ROOMS_RS_ONLY=(agent-rooms)
ORG="p-vbordei"

KEEP=0
FILTER=""
for arg in "$@"; do
  case "$arg" in
    --keep) KEEP=1 ;;
    *) FILTER="$arg" ;;
  esac
done

TMP=$(mktemp -d -t agent-ports-verify.XXXXXX)
trap '[ "$KEEP" -eq 0 ] && rm -rf "$TMP"' EXIT
echo "Workspace: $TMP"
echo ""

G='\033[32m'; R='\033[31m'; Y='\033[33m'; N='\033[0m'
declare -a RESULTS=()  # "<repo>|<lang>|<status>|<count>"

verify_py() {
  local repo="$1"
  local name="$repo-py"
  local url="https://github.com/$ORG/$name.git"
  local dir="$TMP/$name"
  local log="$TMP/$name.log"
  echo "→ $name ..."
  if ! git clone -q --depth 1 "$url" "$dir" >"$log" 2>&1; then
    RESULTS+=("$repo|py|CLONE_FAIL|")
    printf "  ${R}CLONE FAIL${N} (see $log)\n"
    return
  fi
  if ! (cd "$dir" && uv venv -p 3.13 -q && uv pip install -q -e ".[dev]") >>"$log" 2>&1; then
    RESULTS+=("$repo|py|INSTALL_FAIL|")
    printf "  ${R}INSTALL FAIL${N} (see $log)\n"
    return
  fi
  local out
  out=$(cd "$dir" && uv run pytest -q 2>&1)
  echo "$out" >>"$log"
  if echo "$out" | tail -3 | grep -qE '[0-9]+ passed' && ! echo "$out" | grep -qE 'failed|error '; then
    local n=$(echo "$out" | tail -3 | grep -oE '[0-9]+ passed' | head -1 | grep -oE '[0-9]+')
    RESULTS+=("$repo|py|PASS|$n")
    printf "  ${G}PASS${N} py — %s tests\n" "$n"
  else
    RESULTS+=("$repo|py|TEST_FAIL|")
    printf "  ${R}TEST FAIL${N} py (see $log)\n"
  fi
}

verify_rs() {
  local repo="$1"
  local name="$repo-rs"
  local url="https://github.com/$ORG/$name.git"
  local dir="$TMP/$name"
  local log="$TMP/$name.log"
  echo "→ $name ..."
  if ! git clone -q --depth 1 "$url" "$dir" >"$log" 2>&1; then
    RESULTS+=("$repo|rs|CLONE_FAIL|")
    printf "  ${R}CLONE FAIL${N} (see $log)\n"
    return
  fi
  local out
  out=$(cd "$dir" && cargo test --quiet 2>&1)
  echo "$out" >>"$log"
  local fail_count=$(echo "$out" | grep -cE 'test result: FAILED|FAILED \(')
  local total=$(echo "$out" | grep -E 'test result: ok' | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' | awk '{s+=$1} END {print s+0}')
  if [ "$fail_count" -eq 0 ] && [ "${total:-0}" -gt 0 ]; then
    RESULTS+=("$repo|rs|PASS|$total")
    printf "  ${G}PASS${N} rs — %s tests\n" "$total"
  else
    RESULTS+=("$repo|rs|TEST_FAIL|$total")
    printf "  ${R}TEST FAIL${N} rs (see $log)\n"
  fi
}

ALL=("${REPOS[@]}" "${ROOMS_RS_ONLY[@]}")
if [ -n "$FILTER" ]; then
  ALL=()
  for r in "${REPOS[@]}" "${ROOMS_RS_ONLY[@]}"; do
    [[ "$r" == *"$FILTER"* ]] && ALL+=("$r")
  done
fi

for r in "${ALL[@]}"; do
  if [[ " ${ROOMS_RS_ONLY[*]} " == *" $r "* ]]; then
    verify_rs "$r"
  else
    verify_py "$r"
    verify_rs "$r"
  fi
done

echo ""
echo "=== Summary ==="
printf "%-22s  %-4s  %-12s  %s\n" "REPO" "LANG" "STATUS" "TESTS"
printf "%-22s  %-4s  %-12s  %s\n" "----" "----" "------" "-----"
fails=0
for line in "${RESULTS[@]}"; do
  IFS='|' read -r repo lang status count <<< "$line"
  [[ "$status" != "PASS" ]] && fails=$((fails+1))
  printf "%-22s  %-4s  %-12s  %s\n" "$repo" "$lang" "$status" "${count:-—}"
done
echo ""
total=${#RESULTS[@]}
passed=$((total - fails))
echo "${passed}/${total} green."
[ "$KEEP" -eq 1 ] && echo "Workspace kept at $TMP"

[ "$fails" -gt 0 ] && exit 1
exit 0
