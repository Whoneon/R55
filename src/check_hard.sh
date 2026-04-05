#!/usr/bin/env bash
#
# Check status of hard sub-cube solving (sub-sub-cubing phase).
#
# Usage:
#   ./check_hard.sh              # check all cubes (local + server)
#   ./check_hard.sh 3            # check specific cube
#   ./check_hard.sh --detail 3   # detailed view per sub-cube
#
set -uo pipefail

SATDIR="$(cd "$(dirname "$0")/../results/sat" && pwd)"

echo "============================================"
echo "  Hard Sub-cube Solving — Status"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"
echo ""

check_cube() {
    local cube="$1"
    local base_dir="$2"
    local detail="${3:-false}"

    local hard_dir="$base_dir/hard_subcubes_${cube}"
    local results_dir="$base_dir/subcube_results_${cube}"

    if [[ ! -d "$hard_dir" ]]; then
        echo "  Cube $cube: not started (no hard_subcubes dir)"
        return
    fi

    # Count hard sub-cubes being processed
    local total_hard
    total_hard=$(find "$hard_dir" -maxdepth 1 -name 'sc_*' -type d | wc -l)

    local ssc_done=0 ssc_running=0 ssc_pending=0
    local unsat=0 sat=0 incomplete=0 ssc_fail=0

    for sc_dir in "$hard_dir"/sc_*; do
        [[ -d "$sc_dir" ]] || continue
        local sc_idx
        sc_idx=$(basename "$sc_dir" | sed 's/sc_//')
        local sf="$sc_dir/summary.txt"

        if [[ -f "$sf" ]]; then
            local status
            status=$(head -1 "$sf")
            case "$status" in
                UNSAT)
                    ssc_done=$((ssc_done + 1))
                    unsat=$((unsat + 1))
                    [[ "$detail" == "true" ]] && echo "    sc $sc_idx: UNSAT — $(tail -1 "$sf")"
                    ;;
                SAT)
                    ssc_done=$((ssc_done + 1))
                    sat=$((sat + 1))
                    [[ "$detail" == "true" ]] && echo "    sc $sc_idx: *** SAT *** — $(tail -1 "$sf")"
                    ;;
                INCOMPLETE)
                    incomplete=$((incomplete + 1))
                    [[ "$detail" == "true" ]] && echo "    sc $sc_idx: INCOMPLETE — $(tail -1 "$sf")"
                    ;;
                SSC_FAIL)
                    ssc_fail=$((ssc_fail + 1))
                    [[ "$detail" == "true" ]] && echo "    sc $sc_idx: SSC_FAIL"
                    ;;
            esac
        elif [[ -f "$sc_dir/subsub.icnf" ]]; then
            # Sub-sub-cubing done, solving in progress
            local n_ssc
            n_ssc=$(grep -c '^a ' "$sc_dir/subsub.icnf" 2>/dev/null || echo 0)
            local n_solved
            n_solved=$(find "$sc_dir/results" -name 'ssc_*.result' 2>/dev/null | wc -l)
            ssc_running=$((ssc_running + 1))
            if [[ "$detail" == "true" ]]; then
                local n_unsat
                n_unsat=$(grep -rl '^UNSAT$' "$sc_dir/results/" 2>/dev/null | grep -c '\.result$' || true)
                echo "    sc $sc_idx: solving $n_solved/$n_ssc sub-sub-cubes (UNSAT=$n_unsat)"
            fi
        elif [[ -f "$sc_dir/parent.icnf" ]]; then
            # Sub-sub-cubing in progress
            ssc_running=$((ssc_running + 1))
            [[ "$detail" == "true" ]] && echo "    sc $sc_idx: sub-sub-cubing..."
        else
            ssc_pending=$((ssc_pending + 1))
        fi
    done

    # Also count how many of the original 85 TIMEOUT results have been updated
    local fixed=0
    local total_timeout
    total_timeout=$(grep -rl '^TIMEOUT$' "$results_dir"/ 2>/dev/null | grep -c '\.result$' || true)
    local total_unsat_parent
    total_unsat_parent=$(grep -rl '^UNSAT$' "$results_dir"/ 2>/dev/null | grep -c '\.result$' || true)

    printf "  Cube %2d: %d/%d hard done" "$cube" "$ssc_done" 85
    printf "  [UNSAT=%d SAT=%d]" "$unsat" "$sat"
    printf "  running=%d incomplete=%d" "$ssc_running" "$incomplete"
    echo ""
    printf "          parent results: %d/4483 UNSAT, %d TIMEOUT remaining\n" \
           "$total_unsat_parent" "$total_timeout"

    if [[ $sat -gt 0 ]]; then
        echo "          *** SAT FOUND! ***"
    elif [[ $ssc_done -eq 85 && $sat -eq 0 && $incomplete -eq 0 ]]; then
        echo "          *** ALL 85 HARD SUB-CUBES UNSAT → CUBE $cube FULLY UNSAT ***"
    fi
}

# Check local cubes
echo "=== LOCAL ==="
for c in 3 6 10; do
    if [[ -n "${1:-}" && "$1" != "--detail" && "$1" != "$c" ]]; then continue; fi
    detail="false"
    [[ "${1:-}" == "--detail" ]] && detail="true"
    check_cube "$c" "$SATDIR" "$detail"
done
echo ""

# Check server cubes
echo "=== SERVER (hatweb-server) ==="
for c in 7 9; do
    if [[ -n "${1:-}" && "$1" != "--detail" && "$1" != "$c" ]]; then continue; fi
    REMOTE=$(ssh hatweb-server "
        SATDIR=~/R55/results/sat
        HARD_DIR=\$SATDIR/hard_subcubes_${c}
        RESULTS_DIR=\$SATDIR/subcube_results_${c}
        if [[ ! -d \"\$HARD_DIR\" ]]; then
            echo 'NODIR'
            exit
        fi
        done_n=0; unsat_n=0; sat_n=0; running_n=0; incomplete_n=0
        for sd in \$HARD_DIR/sc_*; do
            [[ -d \"\$sd\" ]] || continue
            sf=\"\$sd/summary.txt\"
            if [[ -f \"\$sf\" ]]; then
                s=\$(head -1 \"\$sf\")
                done_n=\$((done_n+1))
                [[ \"\$s\" == 'UNSAT' ]] && unsat_n=\$((unsat_n+1))
                [[ \"\$s\" == 'SAT' ]] && sat_n=\$((sat_n+1))
                [[ \"\$s\" == 'INCOMPLETE' ]] && incomplete_n=\$((incomplete_n+1))
            else
                running_n=\$((running_n+1))
            fi
        done
        tout=\$(grep -rl '^TIMEOUT\$' \"\$RESULTS_DIR\"/ 2>/dev/null | grep -c '\.result\$' || true)
        total_unsat=\$(grep -rl '^UNSAT\$' \"\$RESULTS_DIR\"/ 2>/dev/null | grep -c '\.result\$' || true)
        echo \"\$done_n \$unsat_n \$sat_n \$running_n \$incomplete_n \$tout \$total_unsat\"
    " 2>/dev/null)

    if [[ "$REMOTE" == "NODIR" || -z "$REMOTE" ]]; then
        echo "  Cube $c: not started / unreachable"
    else
        read done_n unsat_n sat_n running_n incomplete_n tout total_unsat <<< "$REMOTE"
        printf "  Cube %2d: %d/%d hard done" "$c" "$done_n" 85
        printf "  [UNSAT=%d SAT=%d]" "$unsat_n" "$sat_n"
        printf "  running=%d incomplete=%d\n" "$running_n" "$incomplete_n"
        printf "          parent results: %d/4483 UNSAT, %d TIMEOUT remaining\n" \
               "$total_unsat" "$tout"
        if [[ $sat_n -gt 0 ]]; then
            echo "          *** SAT FOUND! ***"
        elif [[ $done_n -eq 85 && $sat_n -eq 0 && $incomplete_n -eq 0 ]]; then
            echo "          *** ALL 85 HARD SUB-CUBES UNSAT → CUBE $c FULLY UNSAT ***"
        fi
    fi
done
echo ""

# Grand total
echo "=== OVERALL (including monolithic cubes) ==="
echo "  Cubes 1,2,4,5,8,11: UNSAT (monolithic)"
echo "  Cubes 3,6,7,9,10: sub-cubing + sub-sub-cubing in progress"
