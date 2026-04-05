#!/usr/bin/env bash
#
# Extract solving metrics from all levels into CSV files for analysis/plotting.
# Re-runnable: overwrites output CSVs each time.
#
# Output:
#   results/metrics/level2_metrics.csv
#   results/metrics/level3_metrics.csv
#   results/metrics/level4_metrics.csv  (when available)
#   results/metrics/tension_summary.csv (copy of exact_tension.csv)
#   results/metrics/solving_summary.json
#
set -uo pipefail

BASEDIR="$(cd "$(dirname "$0")/.." && pwd)"
METRICS="$BASEDIR/results/metrics"
mkdir -p "$METRICS"

echo "[extract_metrics] $(date '+%Y-%m-%d %H:%M:%S')"

# ═══════════════════════════════════════════════════════
# Level 2: subcube_results_3 (representative — all cubes identical)
# ═══════════════════════════════════════════════════════
L2DIR="$BASEDIR/results/sat/subcube_results_3"
L2CSV="$METRICS/level2_metrics.csv"

if [[ -d "$L2DIR" ]]; then
    echo "[L2] Extracting from $L2DIR..."
    echo "idx,result,time_s,max_depth,mincheck_calls" > "$L2CSV"
    for f in "$L2DIR"/sc_*.result; do
        [[ -f "$f" ]] || continue
        idx=$(basename "$f" | sed 's/sc_//' | sed 's/\.result//')
        res=$(cat "$f")
        logf="$L2DIR/sc_${idx}.log"
        if [[ -f "$logf" && -s "$logf" ]]; then
            time_s=$(grep "^Total time:" "$logf" 2>/dev/null | head -1 | awk '{print $3}')
            max_d=$(grep "^Maximal depth:" "$logf" 2>/dev/null | head -1 | awk '{print $3}')
            mc_calls=$(grep "Calls:" "$logf" 2>/dev/null | head -1 | awk '{print $2}')
            echo "$idx,$res,${time_s:-},${max_d:-},${mc_calls:-}"
        else
            echo "$idx,$res,,,"
        fi
    done >> "$L2CSV"
    echo "[L2] $(wc -l < "$L2CSV") entries"
fi

# ═══════════════════════════════════════════════════════
# Level 3: canonical_ssc/results
# ═══════════════════════════════════════════════════════
L3DIR="$BASEDIR/results/sat/canonical_ssc/results"
L3CSV="$METRICS/level3_metrics.csv"

if [[ -d "$L3DIR" ]]; then
    echo "[L3] Extracting from $L3DIR..."
    echo "idx,result,time_s,max_depth,avg_depth,mincheck_calls,mincheck_time_s,added_clauses" > "$L3CSV"
    for f in "$L3DIR"/ssc_*.result; do
        [[ -f "$f" ]] || continue
        idx=$(basename "$f" | sed 's/ssc_//' | sed 's/\.result//')
        res=$(cat "$f")
        logf="$L3DIR/ssc_${idx}.log"
        if [[ -f "$logf" && -s "$logf" ]]; then
            time_s=$(grep "^Total time:" "$logf" 2>/dev/null | head -1 | awk '{print $3}')
            max_d=$(grep "^Maximal depth:" "$logf" 2>/dev/null | head -1 | awk '{print $3}')
            avg_d=$(grep "^Average depth:" "$logf" 2>/dev/null | head -1 | awk '{print $3}')
            mc_calls=$(grep "Calls:" "$logf" 2>/dev/null | head -1 | awk '{print $2}')
            mc_time=$(grep "Time in seconds:" "$logf" 2>/dev/null | head -1 | awk '{print $4}')
            mc_clauses=$(grep "Added clauses:" "$logf" 2>/dev/null | head -1 | awk '{print $3}')
            echo "$idx,$res,${time_s:-},${max_d:-},${avg_d:-},${mc_calls:-},${mc_time:-},${mc_clauses:-}"
        else
            echo "$idx,$res,,,,,,"
        fi
    done >> "$L3CSV"
    echo "[L3] $(wc -l < "$L3CSV") entries"
fi

# ═══════════════════════════════════════════════════════
# Level 4: canonical_ssc/level4 (when available)
# ═══════════════════════════════════════════════════════
L4DIR="$BASEDIR/results/sat/canonical_ssc/level4"
L4CSV="$METRICS/level4_metrics.csv"

if [[ -d "$L4DIR" ]]; then
    echo "[L4] Extracting from $L4DIR..."
    echo "parent_ssc,l4_idx,result,time_s,max_depth,avg_depth,mincheck_calls,mincheck_time_s,added_clauses" > "$L4CSV"
    for ssc_dir in "$L4DIR"/ssc_*; do
        [[ -d "$ssc_dir/results" ]] || continue
        parent=$(basename "$ssc_dir" | sed 's/ssc_//')
        for f in "$ssc_dir"/results/l4_*.result; do
            [[ -f "$f" ]] || continue
            l4idx=$(basename "$f" | sed 's/l4_//' | sed 's/\.result//')
            res=$(cat "$f")
            logf="$ssc_dir/results/l4_${l4idx}.log"
            if [[ -f "$logf" && -s "$logf" ]]; then
                time_s=$(grep "^Total time:" "$logf" 2>/dev/null | head -1 | awk '{print $3}')
                max_d=$(grep "^Maximal depth:" "$logf" 2>/dev/null | head -1 | awk '{print $3}')
                avg_d=$(grep "^Average depth:" "$logf" 2>/dev/null | head -1 | awk '{print $3}')
                mc_calls=$(grep "Calls:" "$logf" 2>/dev/null | head -1 | awk '{print $2}')
                mc_time=$(grep "Time in seconds:" "$logf" 2>/dev/null | head -1 | awk '{print $4}')
                mc_clauses=$(grep "Added clauses:" "$logf" 2>/dev/null | head -1 | awk '{print $3}')
                echo "$parent,$l4idx,$res,${time_s:-},${max_d:-},${avg_d:-},${mc_calls:-},${mc_time:-},${mc_clauses:-}"
            else
                echo "$parent,$l4idx,$res,,,,,,"
            fi
        done
    done >> "$L4CSV"
    echo "[L4] $(wc -l < "$L4CSV") entries"
else
    echo "[L4] Not yet available"
fi

# ═══════════════════════════════════════════════════════
# Extension tension
# ═══════════════════════════════════════════════════════
if [[ -f "$BASEDIR/results/exact_tension.csv" ]]; then
    cp "$BASEDIR/results/exact_tension.csv" "$METRICS/tension.csv"
    echo "[tension] Copied ($(wc -l < "$METRICS/tension.csv") entries)"
fi

# ═══════════════════════════════════════════════════════
# Summary JSON
# ═══════════════════════════════════════════════════════
L2_TOTAL=$(tail -n+2 "$L2CSV" 2>/dev/null | wc -l || echo 0)
L2_UNSAT=$(grep -c ",UNSAT," "$L2CSV" 2>/dev/null || true)
L2_TOUT=$(grep -c ",TIMEOUT," "$L2CSV" 2>/dev/null || true)

L3_TOTAL=$(tail -n+2 "$L3CSV" 2>/dev/null | wc -l || echo 0)
L3_UNSAT=$(grep -c ",UNSAT," "$L3CSV" 2>/dev/null || true)
L3_TOUT=$(grep -c ",TIMEOUT," "$L3CSV" 2>/dev/null || true)

cat > "$METRICS/solving_summary.json" << ENDJSON
{
  "extracted_at": "$(date -Iseconds)",
  "levels": {
    "L1": {"cutoff": 50, "total": 11, "unsat": 6, "hard": 5},
    "L2": {"cutoff": 70, "total": 4483, "unsat": $L2_UNSAT, "timeout": $L2_TOUT},
    "L3": {"cutoff": 90, "total": 5439, "solved": $L3_TOTAL, "unsat": $L3_UNSAT, "timeout": $L3_TOUT},
    "L4": {"cutoff": 110, "status": "pending"}
  }
}
ENDJSON

echo ""
echo "[summary] Written to $METRICS/solving_summary.json"
echo "[extract_metrics] Done."
