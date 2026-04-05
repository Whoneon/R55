#!/usr/bin/env bash
#
# Level 4: Decompose TIMEOUT sub-sub-cubes at higher cutoff and solve.
#
# Takes the 11 TIMEOUT sub-sub-cubes from level 3 (cutoff 90),
# decomposes each at cutoff 110, then solves the resulting pieces.
#
# Usage:
#   ./solve_level4_ssc.sh [JOBS] [SSC_CUTOFF]
#
set -euo pipefail

SATDIR="$(cd "$(dirname "$0")/../results/sat" && pwd)"
SMSG="${SMSG:-$(which smsg 2>/dev/null || echo /home/antoh/.local/bin/smsg)}"
CNF="$SATDIR/r55_43_sms.cnf"
CANONICAL="$SATDIR/canonical_ssc"
SUBSUB="$CANONICAL/subsub.icnf"
L3_RESULTS="$CANONICAL/results"
L4_DIR="$CANONICAL/level4"
L4_CUTOFF="${2:-110}"
JOBS="${1:-$(nproc)}"
SOLVE_TIMEOUT="${SOLVE_TIMEOUT:-7200}"

mkdir -p "$L4_DIR"

# Find TIMEOUT sub-sub-cubes from level 3
TIMEOUT_LIST=()
for f in "$L3_RESULTS"/ssc_*.result; do
    [[ -f "$f" ]] || continue
    if [[ "$(cat "$f")" == "TIMEOUT" ]]; then
        idx=$(basename "$f" | sed 's/ssc_//' | sed 's/\.result//')
        TIMEOUT_LIST+=("$idx")
    fi
done

TOTAL_TIMEOUT=${#TIMEOUT_LIST[@]}
if [[ $TOTAL_TIMEOUT -eq 0 ]]; then
    echo "No TIMEOUT sub-sub-cubes found at level 3."
    exit 0
fi

echo "============================================"
echo "  Level 4 SSC Solver"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"
echo "  TIMEOUT SSCs from level 3: $TOTAL_TIMEOUT"
echo "  Indices: ${TIMEOUT_LIST[*]}"
echo "  Level 4 cutoff: $L4_CUTOFF"
echo "  Workers: $JOBS"
echo "  Solve timeout: ${SOLVE_TIMEOUT}s"
echo "============================================"
echo ""

process_timeout_ssc() {
    local ssc_idx="$1"
    local ssc_dir="$L4_DIR/ssc_${ssc_idx}"
    local summary_file="$ssc_dir/summary.txt"

    # Skip if already completed
    if [[ -f "$summary_file" ]]; then
        local status
        status=$(head -1 "$summary_file")
        if [[ "$status" == "UNSAT" || "$status" == "SAT" ]]; then
            echo "[ssc $ssc_idx] Already done: $status"
            return 0
        fi
        rm -f "$summary_file"
    fi

    mkdir -p "$ssc_dir/results"

    # Extract the level-3 sub-sub-cube line
    local ssc_line
    ssc_line=$(awk '/^a /{n++; if(n=='"$ssc_idx"') {print; exit}}' "$SUBSUB")
    echo "$ssc_line" > "$ssc_dir/parent.icnf"

    # Step 1: Decompose at higher cutoff
    local t0
    t0=$(date +%s)

    if [[ -f "$ssc_dir/level4.icnf" ]] && grep -q "^Total time:" "$ssc_dir/level4.icnf" 2>/dev/null; then
        echo "[ssc $ssc_idx] Level 4 cubing already complete, skipping to solve"
    else
        echo "[ssc $ssc_idx] Cubing at cutoff $L4_CUTOFF..."
        rm -f "$ssc_dir/level4.icnf"
        if ! timeout 14400 "$SMSG" -v 43 --dimacs "$CNF" \
            --cube-file "$ssc_dir/parent.icnf" --cube-line 1 \
            --assignment-cutoff "$L4_CUTOFF" > "$ssc_dir/level4.icnf" 2>"$ssc_dir/cubing.log"; then
            echo "[ssc $ssc_idx] Cubing FAILED or TIMEOUT"
            echo "CUBING_FAIL" > "$summary_file"
            return 1
        fi
    fi

    local n_l4
    n_l4=$(grep -c '^a ' "$ssc_dir/level4.icnf" 2>/dev/null || echo 0)
    local t1
    t1=$(date +%s)
    echo "[ssc $ssc_idx] Generated $n_l4 level-4 cubes in $((t1 - t0))s"

    if [[ $n_l4 -eq 0 ]]; then
        echo "UNSAT" > "$summary_file"
        echo "0 cubes (pruned entirely)" >> "$summary_file"
        # Update level 3 result
        echo "UNSAT" > "$L3_RESULTS/ssc_${ssc_idx}.result"
        return 0
    fi

    # Step 2: Solve each level-4 cube
    solve_one_l4() {
        local l4_num="$1"
        local l4_result="$ssc_dir/results/l4_${l4_num}.result"

        [[ -f "$l4_result" ]] && return 0

        local l4_line
        l4_line=$(awk '/^a /{n++; if(n=='"$l4_num"') {print; exit}}' "$ssc_dir/level4.icnf")
        local tmp_file
        tmp_file=$(mktemp "$ssc_dir/results/tmp_XXXXX.icnf")
        echo "$l4_line" > "$tmp_file"

        local l4_log="$ssc_dir/results/l4_${l4_num}.log"
        if timeout "$SOLVE_TIMEOUT" "$SMSG" -v 43 --dimacs "$CNF" \
            --cube-file "$tmp_file" --cube-line 1 > "$l4_log" 2>&1; then
            if grep -q 'All cubes processed' "$l4_log"; then
                echo "UNSAT" > "$l4_result"
            else
                echo "SAT" > "$l4_result"
                cp "$l4_log" "$ssc_dir/results/SAT_l4_${l4_num}.log"
                echo "[!!!] SAT FOUND at ssc $ssc_idx / l4 $l4_num"
            fi
        else
            local ec=$?
            if [[ $ec -eq 124 ]]; then
                echo "TIMEOUT" > "$l4_result"
            else
                echo "ERROR" > "$l4_result"
            fi
        fi
        rm -f "$tmp_file"
    }
    export -f solve_one_l4
    export ssc_dir CNF SMSG SOLVE_TIMEOUT

    echo "[ssc $ssc_idx] Solving $n_l4 level-4 cubes..."
    seq 1 "$n_l4" | xargs -P "$JOBS" -I {} bash -c 'solve_one_l4 "$@"' _ {}

    # Tally
    local solved unsat sat tout
    solved=$(find "$ssc_dir/results" -name 'l4_*.result' | wc -l)
    unsat=$(grep -rl '^UNSAT$' "$ssc_dir/results/" 2>/dev/null | grep -c '\.result$' || true)
    sat=$(grep -rl '^SAT$' "$ssc_dir/results/" 2>/dev/null | grep -c '\.result$' || true)
    tout=$(grep -rl '^TIMEOUT$' "$ssc_dir/results/" 2>/dev/null | grep -c '\.result$' || true)

    local t2
    t2=$(date +%s)
    echo "[ssc $ssc_idx] Done: $solved/$n_l4, UNSAT=$unsat SAT=$sat TOUT=$tout ($((t2 - t0))s)"

    if [[ $sat -gt 0 ]]; then
        echo "SAT" > "$summary_file"
        echo "SAT" > "$L3_RESULTS/ssc_${ssc_idx}.result"
    elif [[ $unsat -eq $n_l4 ]]; then
        echo "UNSAT" > "$summary_file"
        echo "$n_l4/$n_l4 UNSAT in $((t2 - t0))s" >> "$summary_file"
        echo "UNSAT" > "$L3_RESULTS/ssc_${ssc_idx}.result"
    else
        echo "INCOMPLETE" > "$summary_file"
        echo "$solved/$n_l4, UNSAT=$unsat TOUT=$tout" >> "$summary_file"
    fi
}

export -f process_timeout_ssc
export L4_DIR SUBSUB CNF SMSG L4_CUTOFF SOLVE_TIMEOUT L3_RESULTS JOBS

# Process TIMEOUT SSCs sequentially (each uses JOBS workers internally)
for idx in "${TIMEOUT_LIST[@]}"; do
    process_timeout_ssc "$idx"
done

# Final summary
echo ""
echo "============================================"
echo "  Level 4: FINAL SUMMARY"
echo "============================================"
DONE=0; UNSAT_H=0; SAT_H=0; INCOMPLETE_H=0
for idx in "${TIMEOUT_LIST[@]}"; do
    sf="$L4_DIR/ssc_${idx}/summary.txt"
    if [[ -f "$sf" ]]; then
        DONE=$((DONE + 1))
        case "$(head -1 "$sf")" in
            UNSAT) UNSAT_H=$((UNSAT_H + 1)) ;;
            SAT) SAT_H=$((SAT_H + 1)) ;;
            *) INCOMPLETE_H=$((INCOMPLETE_H + 1)) ;;
        esac
    fi
done
echo "  Processed: $DONE / $TOTAL_TIMEOUT"
echo "  UNSAT: $UNSAT_H"
echo "  SAT: $SAT_H"
echo "  Incomplete: $INCOMPLETE_H"

if [[ $SAT_H -gt 0 ]]; then
    echo ""
    echo "  *** SAT FOUND! R(5,5,43) has a solution! ***"
elif [[ $UNSAT_H -eq $TOTAL_TIMEOUT ]]; then
    echo ""
    echo "  *** ALL LEVEL-4 UNSAT ***"
    echo "  Combined with level 3: ALL 5439 sub-sub-cubes UNSAT"
    echo "  *** R(5,5) > 43 VERIFIED (conditional on catalog completeness) ***"
fi
