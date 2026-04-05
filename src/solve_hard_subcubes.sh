#!/usr/bin/env bash
#
# Solve hard (timed-out) sub-cubes via sub-sub-cubing at cutoff 90.
#
# For each hard sub-cube:
#   1. Sub-sub-cube it at cutoff 90 (~27 min, ~5400 sub-sub-cubes)
#   2. Solve each sub-sub-cube with smsg
#   3. Report result
#
# Usage:
#   ./solve_hard_subcubes.sh <cube> [PARALLEL_SSC=4] [PARALLEL_SOLVE=4]
#
# Environment:
#   SMSG      - path to smsg binary (default: auto-detect)
#   SSC_CUTOFF - sub-sub-cube cutoff (default: 90)
#   SOLVE_TIMEOUT - timeout per sub-sub-cube solve in seconds (default: 3600)
#   CUBES_TO_DO - space-separated list of specific hard sub-cube indices to process
#                 (default: auto-detect from TIMEOUT results)
#
set -euo pipefail

CUBE="${1:?Usage: $0 <cube> [PARALLEL_SSC] [PARALLEL_SOLVE]}"
PARALLEL_SSC="${2:-4}"
PARALLEL_SOLVE="${3:-4}"

SATDIR="$(cd "$(dirname "$0")/../results/sat" && pwd)"
SMSG="${SMSG:-$(which smsg 2>/dev/null || echo /home/antoh/.local/bin/smsg)}"
CNF="$SATDIR/r55_43_sms.cnf"
SSC_CUTOFF="${SSC_CUTOFF:-90}"
SOLVE_TIMEOUT="${SOLVE_TIMEOUT:-3600}"
SUBCUBE_FILE="$SATDIR/subcubes_${CUBE}.icnf"
RESULTS_BASE="$SATDIR/subcube_results_${CUBE}"
HARD_DIR="$SATDIR/hard_subcubes_${CUBE}"

mkdir -p "$HARD_DIR"

# Find hard sub-cubes (TIMEOUT results)
if [[ -n "${CUBES_TO_DO:-}" ]]; then
    HARD_LIST=($CUBES_TO_DO)
else
    HARD_LIST=()
    while IFS= read -r f; do
        idx=$(basename "$f" | sed 's/sc_//' | sed 's/\.result//')
        HARD_LIST+=("$idx")
    done < <(grep -rl '^TIMEOUT$' "$RESULTS_BASE"/ 2>/dev/null | grep '\.result$' | sort -t_ -k2 -n)
fi

TOTAL_HARD=${#HARD_LIST[@]}
if [[ $TOTAL_HARD -eq 0 ]]; then
    echo "No hard sub-cubes found for cube $CUBE"
    exit 0
fi

echo "============================================"
echo "  Cube $CUBE: solving $TOTAL_HARD hard sub-cubes"
echo "  Sub-sub-cube cutoff: $SSC_CUTOFF"
echo "  Parallel sub-sub-cubing: $PARALLEL_SSC"
echo "  Parallel solving: $PARALLEL_SOLVE"
echo "============================================"
echo ""

# Process one hard sub-cube: sub-sub-cube then solve all pieces
process_hard() {
    local sc_idx="$1"
    local sc_dir="$HARD_DIR/sc_${sc_idx}"
    local summary_file="$sc_dir/summary.txt"

    # Skip if already completed successfully
    if [[ -f "$summary_file" ]]; then
        local status
        status=$(head -1 "$summary_file")
        if [[ "$status" == "UNSAT" || "$status" == "SAT" ]]; then
            echo "[sc $sc_idx] Already done: $status"
            return 0
        fi
        # SSC_FAIL or INCOMPLETE: remove summary to retry
        rm -f "$summary_file"
    fi

    mkdir -p "$sc_dir"

    # Extract the hard sub-cube line
    local cube_line
    cube_line=$(awk '/^a /{n++; if(n=='"$sc_idx"') {print; exit}}' "$SUBCUBE_FILE")
    echo "$cube_line" > "$sc_dir/parent.icnf"

    # Step 1: Sub-sub-cube at higher cutoff
    local t0
    t0=$(date +%s)

    # Check if sub-sub-cubing already completed
    local ssc_complete=0
    if [[ -f "$sc_dir/subsub.icnf" ]]; then
        if tail -1 "$sc_dir/subsub.icnf" 2>/dev/null | grep -q "^Total time:"; then
            ssc_complete=1
            echo "[sc $sc_idx] Sub-sub-cubing already complete, skipping to solve phase"
        else
            # Incomplete — remove and redo
            echo "[sc $sc_idx] Found incomplete sub-sub-cubing, redoing..."
            rm -f "$sc_dir/subsub.icnf" "$sc_dir/subsub.log"
            rm -rf "$sc_dir/results"
        fi
    fi

    if [[ $ssc_complete -eq 0 ]]; then
        echo "[sc $sc_idx] Sub-sub-cubing at cutoff $SSC_CUTOFF..."
        if ! timeout 14400 "$SMSG" -v 43 --dimacs "$CNF" \
            --cube-file "$sc_dir/parent.icnf" --cube-line 1 \
            --assignment-cutoff "$SSC_CUTOFF" > "$sc_dir/subsub.icnf" 2>"$sc_dir/subsub.log"; then
            echo "[sc $sc_idx] Sub-sub-cubing FAILED or TIMEOUT (14400s)"
            echo "SSC_FAIL" > "$summary_file"
            return 1
        fi
    fi

    local n_ssc
    n_ssc=$(grep -c '^a ' "$sc_dir/subsub.icnf" 2>/dev/null || echo 0)
    local t1
    t1=$(date +%s)
    echo "[sc $sc_idx] Generated $n_ssc sub-sub-cubes in $((t1 - t0))s"

    if [[ $n_ssc -eq 0 ]]; then
        echo "[sc $sc_idx] No sub-sub-cubes — UNSAT by sub-sub-cubing"
        echo "UNSAT" > "$summary_file"
        echo "0 sub-sub-cubes (pruned entirely)" >> "$summary_file"
        return 0
    fi

    # Step 2: Solve each sub-sub-cube
    local solved=0 unsat=0 sat=0 timeout_n=0 errors=0
    mkdir -p "$sc_dir/results"

    solve_one_ssc() {
        local ssc_line_num="$1"
        local ssc_result="$sc_dir/results/ssc_${ssc_line_num}.result"

        [[ -f "$ssc_result" ]] && return 0

        local ssc_line
        ssc_line=$(awk '/^a /{n++; if(n=='"$ssc_line_num"') {print; exit}}' "$sc_dir/subsub.icnf")
        local tmp_file
        tmp_file=$(mktemp "$sc_dir/results/tmp_XXXXX.icnf")
        echo "$ssc_line" > "$tmp_file"

        local ssc_log="$sc_dir/results/ssc_${ssc_line_num}.log"
        if timeout "$SOLVE_TIMEOUT" "$SMSG" -v 43 --dimacs "$CNF" \
            --cube-file "$tmp_file" --cube-line 1 > "$ssc_log" 2>&1; then
            if grep -q 'All cubes processed' "$ssc_log"; then
                echo "UNSAT" > "$ssc_result"
            else
                echo "SAT" > "$ssc_result"
                cp "$ssc_log" "$sc_dir/results/SAT_ssc_${ssc_line_num}.log"
            fi
        else
            local ec=$?
            if [[ $ec -eq 124 ]]; then
                echo "TIMEOUT" > "$ssc_result"
            else
                echo "ERROR" > "$ssc_result"
            fi
        fi
        rm -f "$tmp_file"
    }
    export -f solve_one_ssc
    export sc_dir CNF SMSG SOLVE_TIMEOUT

    echo "[sc $sc_idx] Solving $n_ssc sub-sub-cubes ($PARALLEL_SOLVE workers)..."
    seq 1 "$n_ssc" | xargs -P "$PARALLEL_SOLVE" -I {} bash -c 'solve_one_ssc "$@"' _ {}

    # Tally results
    solved=$(find "$sc_dir/results" -name 'ssc_*.result' | wc -l)
    unsat=$(grep -rl '^UNSAT$' "$sc_dir/results"/ 2>/dev/null | grep -c '\.result$' || true)
    sat=$(grep -rl '^SAT$' "$sc_dir/results"/ 2>/dev/null | grep -c '\.result$' || true)
    timeout_n=$(grep -rl '^TIMEOUT$' "$sc_dir/results"/ 2>/dev/null | grep -c '\.result$' || true)

    local t2
    t2=$(date +%s)
    echo "[sc $sc_idx] Done: $solved/$n_ssc solved, UNSAT=$unsat SAT=$sat TOUT=$timeout_n ($((t2 - t0))s total)"

    if [[ $sat -gt 0 ]]; then
        echo "SAT" > "$summary_file"
        echo "$sat SAT out of $n_ssc sub-sub-cubes" >> "$summary_file"
        # Update parent result
        echo "SAT" > "$RESULTS_BASE/sc_${sc_idx}.result"
    elif [[ $unsat -eq $n_ssc ]]; then
        echo "UNSAT" > "$summary_file"
        echo "$n_ssc/$n_ssc sub-sub-cubes UNSAT in $((t2 - t0))s" >> "$summary_file"
        # Update parent result
        echo "UNSAT" > "$RESULTS_BASE/sc_${sc_idx}.result"
    else
        echo "INCOMPLETE" > "$summary_file"
        echo "$solved/$n_ssc solved, UNSAT=$unsat TOUT=$timeout_n" >> "$summary_file"
    fi
}

export -f process_hard
export HARD_DIR SUBCUBE_FILE CNF SMSG SSC_CUTOFF SOLVE_TIMEOUT RESULTS_BASE PARALLEL_SOLVE

# Run hard sub-cubes with limited parallelism for sub-sub-cubing
# (each sub-sub-cubing uses 1 core, solving uses PARALLEL_SOLVE cores)
# To avoid overloading, we process PARALLEL_SSC hard sub-cubes at a time
printf '%s\n' "${HARD_LIST[@]}" | xargs -P "$PARALLEL_SSC" -I {} bash -c 'process_hard "$@"' _ {}

# Final summary
echo ""
echo "============================================"
echo "  Cube $CUBE: FINAL SUMMARY"
echo "============================================"
DONE=0; UNSAT_H=0; SAT_H=0; INCOMPLETE_H=0
for sc_idx in "${HARD_LIST[@]}"; do
    sf="$HARD_DIR/sc_${sc_idx}/summary.txt"
    if [[ -f "$sf" ]]; then
        DONE=$((DONE + 1))
        case "$(head -1 "$sf")" in
            UNSAT) UNSAT_H=$((UNSAT_H + 1)) ;;
            SAT) SAT_H=$((SAT_H + 1)) ;;
            *) INCOMPLETE_H=$((INCOMPLETE_H + 1)) ;;
        esac
    fi
done
echo "  Processed: $DONE / $TOTAL_HARD"
echo "  UNSAT: $UNSAT_H"
echo "  SAT: $SAT_H"
echo "  Incomplete: $INCOMPLETE_H"

if [[ $SAT_H -gt 0 ]]; then
    echo ""
    echo "  *** SAT FOUND! R(5,5,43) has a solution! ***"
elif [[ $UNSAT_H -eq $TOTAL_HARD ]]; then
    echo ""
    echo "  *** ALL HARD SUB-CUBES UNSAT — Cube $CUBE is fully UNSAT ***"
fi
