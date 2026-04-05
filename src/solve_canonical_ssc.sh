#!/usr/bin/env bash
#
# Solve the canonical sub-sub-cubes (single copy, high parallelism).
#
# This replaces the 425× redundant computation across 5 cubes × 85 hard sub-cubes.
# All sub-sub-cubes are identical regardless of parent cube, so we solve ONCE.
#
# Usage:
#   ./solve_canonical_ssc.sh [JOBS] [RANGE_START] [RANGE_END]
#
set -euo pipefail

SATDIR="$(cd "$(dirname "$0")/../results/sat" && pwd)"
SMSG="${SMSG:-$(which smsg 2>/dev/null || echo /home/antoh/.local/bin/smsg)}"
CNF="$SATDIR/r55_43_sms.cnf"
CANONICAL="$SATDIR/canonical_ssc"
SUBSUB="$CANONICAL/subsub.icnf"
RESULTS="$CANONICAL/results"

JOBS="${1:-$(nproc)}"
RANGE_START="${2:-1}"
RANGE_END="${3:-$(grep -c '^a ' "$SUBSUB")}"
SOLVE_TIMEOUT="${SOLVE_TIMEOUT:-3600}"

mkdir -p "$RESULTS"

TOTAL=$(grep -c '^a ' "$SUBSUB")
ALREADY=$(find "$RESULTS" -name 'ssc_*.result' 2>/dev/null | wc -l)

echo "============================================"
echo "  Canonical SSC Solver"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"
echo "  Total sub-sub-cubes: $TOTAL"
echo "  Already solved: $ALREADY"
echo "  Range: $RANGE_START .. $RANGE_END"
echo "  Workers: $JOBS"
echo "  Timeout: ${SOLVE_TIMEOUT}s"
echo "============================================"
echo ""

solve_one() {
    local ssc_num="$1"
    local result_file="$RESULTS/ssc_${ssc_num}.result"

    # Skip if already solved
    [[ -f "$result_file" ]] && return 0

    # Extract the sub-sub-cube line
    local ssc_line
    ssc_line=$(awk '/^a /{n++; if(n=='"$ssc_num"') {print; exit}}' "$SUBSUB")
    [[ -z "$ssc_line" ]] && return 0

    local tmp_file
    tmp_file=$(mktemp "$RESULTS/tmp_XXXXX.icnf")
    echo "$ssc_line" > "$tmp_file"

    local log_file="$RESULTS/ssc_${ssc_num}.log"
    if timeout "$SOLVE_TIMEOUT" "$SMSG" -v 43 --dimacs "$CNF" \
        --cube-file "$tmp_file" --cube-line 1 > "$log_file" 2>&1; then
        if grep -q 'All cubes processed' "$log_file"; then
            echo "UNSAT" > "$result_file"
        else
            echo "SAT" > "$result_file"
            cp "$log_file" "$RESULTS/SAT_ssc_${ssc_num}.log"
            echo "[!!!] SAT FOUND at ssc $ssc_num"
        fi
    else
        local ec=$?
        if [[ $ec -eq 124 ]]; then
            echo "TIMEOUT" > "$result_file"
        else
            echo "ERROR" > "$result_file"
        fi
    fi
    rm -f "$tmp_file"
}
export -f solve_one
export RESULTS SUBSUB CNF SMSG SOLVE_TIMEOUT

seq "$RANGE_START" "$RANGE_END" | xargs -P "$JOBS" -I {} bash -c 'solve_one "$@"' _ {}

# Summary
echo ""
echo "============================================"
echo "  DONE — $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"
DONE=$(find "$RESULTS" -name 'ssc_*.result' | wc -l)
UNSAT=$(grep -rl '^UNSAT$' "$RESULTS"/ 2>/dev/null | grep -c '\.result$' || true)
SAT=$(grep -rl '^SAT$' "$RESULTS"/ 2>/dev/null | grep -c '\.result$' || true)
TOUT=$(grep -rl '^TIMEOUT$' "$RESULTS"/ 2>/dev/null | grep -c '\.result$' || true)
echo "  Solved: $DONE / $TOTAL"
echo "  UNSAT: $UNSAT"
echo "  SAT: $SAT"
echo "  TIMEOUT: $TOUT"
echo "  Remaining: $((TOTAL - DONE))"

if [[ $SAT -gt 0 ]]; then
    echo ""
    echo "  *** SAT FOUND! R(5,5,43) has a solution! ***"
elif [[ $DONE -eq $TOTAL && $TOUT -eq 0 ]]; then
    echo ""
    echo "  *** ALL UNSAT ***"
fi
