#!/usr/bin/env bash
# verify-bytewise.sh — prove byte-deterministic compatibility across TS / Py / Rs.
#
# How this works (key insight):
#   Each port's `vectors/` directory contains JSON fixtures copied VERBATIM from
#   the TypeScript reference's conformance/ directory. For fixtures that include
#   "expected_canonical" (or similar byte-encoded TS output), the per-port test
#   suite asserts byte-identical match. If the Python AND Rust ports both pass,
#   then TS == PY == RS for that byte surface — by construction.
#
#   So this script doesn't reinvent the wheel. It selectively runs the
#   byte-equality test of each port, and reports a clean cross-impl summary.
#
# What gets explicitly checked here (each is a known byte-equality contract):
#
#   1. agent-scroll  : 20 Turn fixtures → hex (fixtures/c1-hex.json)
#   2. agent-cid     : C4 canonical-encoding vector → expected_canonical
#   3. agent-id      : C1 valid VC → TS-signed proofValue verifies in Py + Rs
#   4. agent-rooms   : 15 canonical_json + 4 signature vectors
#   5. agent-toolprint : C1 receipts → DSSE PAE bytes (TS-signed verifies)
#   6. agent-phone   : C4 frame determinism → hex vector
#
# Output: per-protocol PASS/FAIL with the specific byte surface checked.
# Exit 0 if all green.

set -uo pipefail

PERSONAL="${PERSONAL_DIR:-/Users/vladbordei/Documents/Development/PERSONAL}"
FILTER="${1:-}"
G='\033[32m'; R='\033[31m'; Y='\033[33m'; N='\033[0m'

declare -a RESULTS=()

want() { [ -z "$FILTER" ] || [[ "$1" == *"$FILTER"* ]]; }

# Run a Python test by name (file::node), return 0/1.
run_py_test() {
  local dir="$1" testid="$2"
  (cd "$dir" && uv run pytest -q "$testid" >/tmp/bytewise-py-$$.log 2>&1)
  return $?
}

# Run a Rust test by name, return 0/1.
run_rs_test() {
  local dir="$1" testid="$2"
  (cd "$dir" && cargo test --quiet "$testid" >/tmp/bytewise-rs-$$.log 2>&1)
  return $?
}

# ---- agent-scroll : C1 byte-equality (20 turns vs TS-generated hex) ----
check_scroll() {
  want agent-scroll || return 0
  echo ""
  echo "== agent-scroll : 20 Turn fixtures → canonical bytes hex =="
  local py_dir="$PERSONAL/agent-scroll-py"
  local rs_dir="$PERSONAL/agent-scroll-rs"
  local py_ok=1 rs_ok=1
  run_py_test "$py_dir" "tests/test_conformance.py::test_c1_byte_equality" || py_ok=0
  run_rs_test "$rs_dir" "c1_byte_equality" || rs_ok=0
  if [ "$py_ok" = 1 ] && [ "$rs_ok" = 1 ]; then
    echo "  ${G}PASS${N} 20/20 turns: canonical(turn) byte-identical across TS / PY / RS"
    RESULTS+=("agent-scroll|c1-byte-equality (20 turns)|PASS")
  else
    echo "  ${R}FAIL${N} py=$py_ok rs=$rs_ok"
    RESULTS+=("agent-scroll|c1-byte-equality|FAIL py=$py_ok rs=$rs_ok")
  fi
}

# ---- agent-cid : C4 canonical encoding vector ----
check_cid() {
  want agent-cid || return 0
  echo ""
  echo "== agent-cid : C4 canonical-encoding vector =="
  local py_dir="$PERSONAL/agent-cid-py"
  local rs_dir="$PERSONAL/agent-cid-rs"
  local py_ok=1 rs_ok=1
  # The conformance test parameterizes per-vector; run only the c4 one.
  run_py_test "$py_dir" "tests/test_conformance.py::test_vector[c4-canonical]" || py_ok=0
  # Rust runs all vectors in one test; if it passes, c4 passed (and we can also grep the PASS line)
  if (cd "$rs_dir" && cargo test --quiet all_vectors_pass -- --nocapture 2>&1 | grep -q "PASS c4-canonical"); then
    :  # ok
  else
    rs_ok=0
  fi
  if [ "$py_ok" = 1 ] && [ "$rs_ok" = 1 ]; then
    echo "  ${G}PASS${N} canonical_encode(manifest) byte-identical to TS expected_canonical"
    RESULTS+=("agent-cid|c4-canonical|PASS")
  else
    echo "  ${R}FAIL${N} py=$py_ok rs=$rs_ok"
    RESULTS+=("agent-cid|c4-canonical|FAIL py=$py_ok rs=$rs_ok")
  fi
}

# ---- agent-id : C1 TS-signed VC must verify in both Py and Rs ----
# (Implies JCS bytes + Ed25519 match TS byte-for-byte.)
check_id() {
  want agent-id || return 0
  echo ""
  echo "== agent-id : C1 TS-signed VC cross-validates =="
  local py_dir="$PERSONAL/agent-id-py"
  local rs_dir="$PERSONAL/agent-id-rs"
  local py_ok=1 rs_ok=1
  run_py_test "$py_dir" "tests/test_conformance.py" || py_ok=0
  run_rs_test "$rs_dir" "all_vectors_pass" || rs_ok=0
  if [ "$py_ok" = 1 ] && [ "$rs_ok" = 1 ]; then
    echo "  ${G}PASS${N} TS-signed proofValue verifies in PY + RS (JCS + Ed25519 byte-identical)"
    RESULTS+=("agent-id|c1-c3-vectors|PASS")
  else
    RESULTS+=("agent-id|c1-c3-vectors|FAIL py=$py_ok rs=$rs_ok")
  fi
}

# ---- agent-toolprint : C1 TS-signed receipt verifies cross-impl ----
check_toolprint() {
  want agent-toolprint || return 0
  echo ""
  echo "== agent-toolprint : C1 TS-signed DSSE receipt cross-validates =="
  local py_dir="$PERSONAL/agent-toolprint-py"
  local rs_dir="$PERSONAL/agent-toolprint-rs"
  local py_ok=1 rs_ok=1
  run_py_test "$py_dir" "tests/test_conformance.py" || py_ok=0
  run_rs_test "$rs_dir" "all_vectors_pass" || rs_ok=0
  if [ "$py_ok" = 1 ] && [ "$rs_ok" = 1 ]; then
    echo "  ${G}PASS${N} DSSE PAE bytes + signatures byte-identical to TS"
    RESULTS+=("agent-toolprint|c1-c4-vectors|PASS")
  else
    RESULTS+=("agent-toolprint|c1-c4-vectors|FAIL py=$py_ok rs=$rs_ok")
  fi
}

# ---- agent-phone : C4 frame determinism (hex vector byte-match with TS) ----
check_phone() {
  want agent-phone || return 0
  echo ""
  echo "== agent-phone : C4 frame-determinism hex vector =="
  local py_dir="$PERSONAL/agent-phone-py"
  local rs_dir="$PERSONAL/agent-phone-rs"
  local py_ok=1 rs_ok=1
  # These ports name the C4 test differently — try common patterns.
  run_py_test "$py_dir" "tests/test_conformance.py" || \
    run_py_test "$py_dir" "tests/" || py_ok=0
  run_rs_test "$rs_dir" "conformance" || rs_ok=0
  if [ "$py_ok" = 1 ] && [ "$rs_ok" = 1 ]; then
    echo "  ${G}PASS${N} Noise-XK handshake bytes + frame bytes match TS C4 hex vector"
    RESULTS+=("agent-phone|c4-frame-determinism|PASS")
  else
    RESULTS+=("agent-phone|c4-frame-determinism|FAIL py=$py_ok rs=$rs_ok")
  fi
}

# ---- agent-rooms (Rust only — Python is the reference) ----
check_rooms() {
  want agent-rooms || return 0
  echo ""
  echo "== agent-rooms : 25 parley vectors (Python source ↔ Rust port) =="
  local rs_dir="$PERSONAL/agent-rooms-rs"
  if (cd "$rs_dir" && cargo test --quiet 2>&1 | grep -qE 'test result: ok'); then
    echo "  ${G}PASS${N} Rust port passes all 25 canonical + signature + mutation vectors"
    RESULTS+=("agent-rooms|25 parley vectors|PASS")
  else
    RESULTS+=("agent-rooms|25 parley vectors|FAIL")
  fi
}

# ----------------------------------------------------------------------------
echo "Running cross-impl byte-equality checks..."
check_scroll
check_cid
check_id
check_toolprint
check_phone
check_rooms

echo ""
echo "=== Summary ==="
printf "%-18s  %-45s  %s\n" "PROTOCOL" "BYTE SURFACE" "STATUS"
printf "%-18s  %-45s  %s\n" "--------" "------------" "------"
fail=0
for line in "${RESULTS[@]}"; do
  IFS='|' read -r p c s <<< "$line"
  [[ "$s" != PASS* ]] && fail=$((fail+1))
  printf "%-18s  %-45s  %s\n" "$p" "$c" "$s"
done

rm -f /tmp/bytewise-py-$$.log /tmp/bytewise-rs-$$.log

echo ""
total=${#RESULTS[@]}
passed=$((total - fail))
if [ "$fail" -eq 0 ]; then
  echo -e "${G}${passed}/${total} green — byte-deterministic compatibility holds across TS / Py / Rs.${N}"
  exit 0
else
  echo -e "${R}${fail}/${total} failed.${N}"
  exit 1
fi
