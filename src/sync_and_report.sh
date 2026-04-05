#!/usr/bin/env bash
# Sync + progress report
/home/antoh/Desktop/R55/src/sync_canonical_results.sh
DIR="/home/antoh/Desktop/R55/results/sat/canonical_ssc/results"
total=$(ls "$DIR"/ssc_*.result 2>/dev/null | wc -l)
unsat=$(grep -rl '^UNSAT$' "$DIR"/ 2>/dev/null | grep -c '\.result$' || true)
tout=$(grep -rl '^TIMEOUT$' "$DIR"/ 2>/dev/null | grep -c '\.result$' || true)
echo "[$(date '+%H:%M')] $total/5439 (UNSAT=$unsat TIMEOUT=$tout rimanenti=$((5439-total)))"
