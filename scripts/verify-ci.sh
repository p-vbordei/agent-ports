#!/usr/bin/env bash
# verify-ci.sh — query GitHub Actions for each port and report latest run status.
# Fastest: no local build. Trusts that GitHub CI is the source of truth.
#
# Usage:
#   ./scripts/verify-ci.sh            # all 23 ports
#   ./scripts/verify-ci.sh agent-id
#
# Exit: 0 if all latest runs are 'success' or 'in_progress', 1 otherwise.

set -uo pipefail

REPOS=(
  agent-id agent-cid agent-scroll agent-rerun agent-toolprint
  agent-launch agent-publish agent-fleet agent-ask agent-phone agent-pay
)
ROOMS_RS_ONLY=(agent-rooms)
ORG="p-vbordei"
FILTER="${1:-}"

G='\033[32m'; R='\033[31m'; Y='\033[33m'; N='\033[0m'

check() {
  local repo="$1"
  local out
  out=$(gh run list --repo "$ORG/$repo" --limit 1 --json status,conclusion,workflowName,headBranch 2>/dev/null)
  if [ -z "$out" ] || [ "$out" = "[]" ]; then
    printf "${Y}NONE${N}     %-25s  no runs yet (CI may not have triggered)\n" "$repo"
    return 2
  fi
  local status conclusion
  status=$(echo "$out" | jq -r '.[0].status')
  conclusion=$(echo "$out" | jq -r '.[0].conclusion // "null"')
  case "$status:$conclusion" in
    completed:success)
      printf "${G}PASS${N}     %-25s  CI green\n" "$repo"
      return 0 ;;
    in_progress:*|queued:*|requested:*)
      printf "${Y}RUNNING${N}  %-25s  $status\n" "$repo"
      return 2 ;;
    completed:*)
      printf "${R}FAIL${N}     %-25s  $conclusion\n" "$repo"
      return 1 ;;
    *)
      printf "${Y}?${N}        %-25s  $status / $conclusion\n" "$repo"
      return 2 ;;
  esac
}

ALL=()
for r in "${REPOS[@]}"; do
  ALL+=("$r-py" "$r-rs")
done
ALL+=("agent-rooms-rs")

if [ -n "$FILTER" ]; then
  filtered=()
  for r in "${ALL[@]}"; do
    [[ "$r" == *"$FILTER"* ]] && filtered+=("$r")
  done
  ALL=("${filtered[@]}")
fi

echo "Checking GitHub Actions status for ${#ALL[@]} repos..."
echo ""
fail=0
pending=0
ok=0
for repo in "${ALL[@]}"; do
  check "$repo"
  code=$?
  case $code in
    0) ok=$((ok+1)) ;;
    1) fail=$((fail+1)) ;;
    2) pending=$((pending+1)) ;;
  esac
done
echo ""
echo "ok=$ok  fail=$fail  pending/missing=$pending  total=${#ALL[@]}"
[ "$fail" -gt 0 ] && exit 1
exit 0
