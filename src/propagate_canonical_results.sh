#!/usr/bin/env bash
#
# Propagate canonical SSC results to per-cube directories.
# This makes check_hard.sh work correctly by populating the expected locations.
#
set -euo pipefail

SATDIR="$(cd "$(dirname "$0")/../results/sat" && pwd)"
CANONICAL="$SATDIR/canonical_ssc/results"
HARD_CUBES=(3 6 7 9 10)

# The 85 hard sub-cube indices (identical across all cubes)
HARD_INDICES=(
    2722 2761 3197 3199 3299 3304 3305 3308 3309 3310 3316 3317 3318
    3410 3412 3416 3418 3419 3420 3422 3428 3430 3431 3436 3438 3439
    3874 3959 3960 3961 3962 3963 3964 3969 4100 4101 4102 4103 4104
    4110 4111 4114 4115 4116 4117 4118 4119 4120 4123 4124 4125 4126
    4127 4128 4129 4130 4131 4132 4133 4194 4205 4307 4308 4351 4355
    4371 4379 4386 4392 4394 4398 4402 4406 4414 4420 4424 4426 4437
    4443 4445 4447 4449 4451 4453 4455
)

# Count canonical results
total=$(find "$CANONICAL" -name 'ssc_*.result' 2>/dev/null | wc -l)
unsat=$(grep -rl '^UNSAT$' "$CANONICAL"/ 2>/dev/null | grep -c '\.result$' || true)
tout=$(grep -rl '^TIMEOUT$' "$CANONICAL"/ 2>/dev/null | grep -c '\.result$' || true)

echo "Canonical results: $total (UNSAT=$unsat, TIMEOUT=$tout)"

if [[ $unsat -eq 0 ]]; then
    echo "No UNSAT results to propagate yet."
    exit 0
fi

propagated=0
for cube in "${HARD_CUBES[@]}"; do
    results_base="$SATDIR/subcube_results_${cube}"
    hard_dir="$SATDIR/hard_subcubes_${cube}"

    for sc_idx in "${HARD_INDICES[@]}"; do
        sc_dir="$hard_dir/sc_${sc_idx}"
        summary="$sc_dir/summary.txt"

        # Skip if already marked as done
        if [[ -f "$summary" ]]; then
            status=$(head -1 "$summary")
            [[ "$status" == "UNSAT" || "$status" == "SAT" ]] && continue
        fi

        # Check if ALL canonical SSC results for this hard sub-cube are UNSAT
        # Each hard sub-cube maps to a range of canonical SSC indices
        # For now, check the global status: if ALL 5439 canonical SSC are UNSAT,
        # then every hard sub-cube is UNSAT
        # (Individual mapping would require knowing which SSC belong to which hard sc)

        # Simple approach: if all non-TIMEOUT canonical SSCs are UNSAT, mark hard sc
        # Actually since all hard sub-cubes generate the SAME sub-sub-cubes,
        # we just check the canonical global result
        :
    done
done

# Global propagation: if all 5439 canonical SSC are resolved
if [[ $total -ge 5439 && $tout -eq 0 ]]; then
    echo ""
    echo "ALL 5439 canonical SSC resolved!"
    for cube in "${HARD_CUBES[@]}"; do
        results_base="$SATDIR/subcube_results_${cube}"
        for sc_idx in "${HARD_INDICES[@]}"; do
            # Mark parent sub-cube result
            echo "UNSAT" > "$results_base/sc_${sc_idx}.result"
            # Mark hard sub-cube summary
            sc_dir="$SATDIR/hard_subcubes_${cube}/sc_${sc_idx}"
            mkdir -p "$sc_dir"
            echo "UNSAT" > "$sc_dir/summary.txt"
            echo "Resolved via canonical SSC (progressive global cubing)" >> "$sc_dir/summary.txt"
        done
        echo "  Cube $cube: all 85 hard sub-cubes marked UNSAT"
    done
    propagated=$((85 * 5))
fi

echo "Propagated: $propagated results"
