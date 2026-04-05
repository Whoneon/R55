#!/usr/bin/env bash
# Quick status check for all sub-cube solving tasks.
# Usage: ./src/check_all.sh
set -uo pipefail

SATDIR="$(cd "$(dirname "$0")/../results/sat" && pwd)"
SCRIPT="$(dirname "$0")/solve_subcubes.sh"

echo "============================================"
echo "  R(5,5,43) SMS Cube Solving — Status"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"
echo ""

echo "=== COMPLETED CUBES (monolithic) ==="
echo "  Cube 1: UNSAT (195s)"
echo "  Cube 2: UNSAT (1s)"
echo "  Cube 4: UNSAT (1.3s)"
echo "  Cube 5: UNSAT (762s)"
echo "  Cube 8: UNSAT (47s)"
echo "  Cube 11: UNSAT (58s)"
echo ""

echo "=== LOCAL (this machine) ==="
for c in 3 6 10; do
    DIR="$SATDIR/subcube_results_${c}"
    if [[ -d "$DIR" ]]; then
        TOTAL=4483
        DONE=$(find "$DIR" -name 'sc_*.result' 2>/dev/null | wc -l)
        UNSAT=$(grep -rl '^UNSAT$' "$DIR"/ 2>/dev/null | grep -c '\.result$' || true)
        SAT=$(grep -rl '^SAT$' "$DIR"/ 2>/dev/null | grep -c '\.result$' || true)
        TIMEOUT_N=$(grep -rl '^TIMEOUT$' "$DIR"/ 2>/dev/null | grep -c '\.result$' || true)
        PCT=$(( DONE * 100 / TOTAL ))
        STATUS="IN PROGRESS"
        [[ $DONE -eq $TOTAL && $SAT -eq 0 && $TIMEOUT_N -eq 0 ]] && STATUS="✓ ALL UNSAT"
        [[ $SAT -gt 0 ]] && STATUS="★ SAT FOUND!"
        printf "  Cube %2d: %4d/%d (%3d%%) UNSAT=%d SAT=%d TOUT=%d  [%s]\n" \
               "$c" "$DONE" "$TOTAL" "$PCT" "$UNSAT" "$SAT" "$TIMEOUT_N" "$STATUS"
    else
        echo "  Cube $c: not started"
    fi
done
echo ""

echo "=== SERVER (hatweb-server) ==="
for c in 7 9; do
    REMOTE=$(ssh hatweb-server "
        DIR=~/R55/results/sat/subcube_results_${c}
        if [[ -d \"\$DIR\" ]]; then
            TOTAL=4483
            DONE=\$(find \"\$DIR\" -name 'sc_*.result' 2>/dev/null | wc -l)
            UNSAT=\$(grep -rl '^UNSAT\$' \"\$DIR\"/ 2>/dev/null | grep -c '\.result\$' || true)
            SAT=\$(grep -rl '^SAT\$' \"\$DIR\"/ 2>/dev/null | grep -c '\.result\$' || true)
            TOUT=\$(grep -rl '^TIMEOUT\$' \"\$DIR\"/ 2>/dev/null | grep -c '\.result\$' || true)
            echo \"\$DONE \$UNSAT \$SAT \$TOUT\"
        else
            echo 'NODIR'
        fi
    " 2>/dev/null)
    if [[ "$REMOTE" == "NODIR" || -z "$REMOTE" ]]; then
        echo "  Cube $c: not started / unreachable"
    else
        read DONE UNSAT SAT TIMEOUT_N <<< "$REMOTE"
        TOTAL=4483
        PCT=$(( DONE * 100 / TOTAL ))
        STATUS="IN PROGRESS"
        [[ $DONE -eq $TOTAL && $SAT -eq 0 && $TIMEOUT_N -eq 0 ]] && STATUS="✓ ALL UNSAT"
        [[ $SAT -gt 0 ]] && STATUS="★ SAT FOUND!"
        printf "  Cube %2d: %4d/%d (%3d%%) UNSAT=%d SAT=%d TOUT=%d  [%s]\n" \
               "$c" "$DONE" "$TOTAL" "$PCT" "$UNSAT" "$SAT" "$TIMEOUT_N" "$STATUS"
    fi
done
echo ""

echo "=== VERIFICATION (extension tension) ==="
VPID=$(pgrep -f "verify_tension_incremental" 2>/dev/null || true)
if [[ -n "$VPID" ]]; then
    echo "  PID $VPID running"
    tail -3 /tmp/verify_tension.log 2>/dev/null | sed 's/^/  /'
else
    echo "  Not running"
    echo "  Last output:"
    tail -5 /tmp/verify_tension.log 2>/dev/null | sed 's/^/  /'
fi
echo ""

# Grand total
echo "=== GRAND TOTAL ==="
TOTAL_DONE=6  # monolithic cubes
TOTAL_CUBES=11
for c in 3 6 10; do
    DIR="$SATDIR/subcube_results_${c}"
    if [[ -d "$DIR" ]]; then
        D=$(find "$DIR" -name 'sc_*.result' 2>/dev/null | wc -l)
        S=$(grep -rl '^SAT$' "$DIR"/ 2>/dev/null | grep -c '\.result$' || true)
        T=$(grep -rl '^TIMEOUT$' "$DIR"/ 2>/dev/null | grep -c '\.result$' || true)
        [[ $D -eq 4483 && $S -eq 0 && $T -eq 0 ]] && TOTAL_DONE=$((TOTAL_DONE + 1))
    fi
done
for c in 7 9; do
    REMOTE=$(ssh hatweb-server "
        DIR=~/R55/results/sat/subcube_results_${c}
        if [[ -d \"\$DIR\" ]]; then
            D=\$(find \"\$DIR\" -name 'sc_*.result' 2>/dev/null | wc -l)
            S=\$(grep -rl '^SAT\$' \"\$DIR\"/ 2>/dev/null | grep -c '\.result\$' || true)
            T=\$(grep -rl '^TIMEOUT\$' \"\$DIR\"/ 2>/dev/null | grep -c '\.result\$' || true)
            [[ \$D -eq 4483 && \$S -eq 0 && \$T -eq 0 ]] && echo DONE || echo WIP
        else
            echo WIP
        fi
    " 2>/dev/null)
    [[ "$REMOTE" == "DONE" ]] && TOTAL_DONE=$((TOTAL_DONE + 1))
done
echo "  Cubes UNSAT: $TOTAL_DONE / $TOTAL_CUBES"
if [[ $TOTAL_DONE -eq $TOTAL_CUBES ]]; then
    echo ""
    echo "  ★★★ ALL 11 CUBES UNSAT — R(5,5,43) has NO solution (SMS verified) ★★★"
fi
