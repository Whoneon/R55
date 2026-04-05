#!/usr/bin/env bash
#
# Solve SMS sub-cubes in parallel across local cores or multiple machines.
#
# Usage:
#   # Local (use all cores):
#   ./solve_subcubes.sh 3
#
#   # Local with N parallel workers:
#   JOBS=8 ./solve_subcubes.sh 3
#
#   # Distributed: split work across machines, then merge results
#   # Machine A (sub-cubes 1-2242):
#   RANGE_START=1 RANGE_END=2242 ./solve_subcubes.sh 3
#   # Machine B (sub-cubes 2243-4483):
#   RANGE_START=2243 RANGE_END=4483 ./solve_subcubes.sh 3
#
#   # After all machines finish, check results:
#   ./solve_subcubes.sh --check 3
#
set -euo pipefail

SATDIR="$(cd "$(dirname "$0")/../results/sat" && pwd)"
SMSG="${SMSG:-/home/antoh/.local/bin/smsg}"
CNF="$SATDIR/r55_43_sms.cnf"
JOBS="${JOBS:-$(nproc)}"
TIMEOUT="${TIMEOUT:-3600}"  # per sub-cube timeout in seconds

if [[ "${1:-}" == "--check" ]]; then
    shift
    CUBE="$1"
    RESULTS="$SATDIR/subcube_results_${CUBE}"
    TOTAL=$(grep -c '^a ' "$SATDIR/subcubes_${CUBE}.icnf")
    DONE=$(find "$RESULTS" -name 'sc_*.result' 2>/dev/null | wc -l)
    UNSAT=$(grep -rl '^UNSAT$' "$RESULTS"/ 2>/dev/null | grep -c '\.result$' || true)
    SAT=$(grep -rl '^SAT$' "$RESULTS"/ 2>/dev/null | grep -c '\.result$' || true)
    TIMEOUT_COUNT=$(grep -rl '^TIMEOUT$' "$RESULTS"/ 2>/dev/null | grep -c '\.result$' || true)
    ERROR=$(grep -rl '^ERROR$' "$RESULTS"/ 2>/dev/null | grep -c '\.result$' || true)
    echo "=== Cube $CUBE: $DONE / $TOTAL sub-cubes solved ==="
    echo "  UNSAT:    $UNSAT"
    echo "  SAT:      $SAT"
    echo "  TIMEOUT:  $TIMEOUT_COUNT"
    echo "  ERROR:    $ERROR"
    echo "  MISSING:  $((TOTAL - DONE))"
    if [[ "$SAT" -gt 0 ]]; then
        echo "*** SAT FOUND — R(5,5,43) has a solution! ***"
        grep -rl '^SAT$' "$RESULTS"/*.result
    elif [[ "$DONE" -eq "$TOTAL" && "$TIMEOUT_COUNT" -eq 0 && "$ERROR" -eq 0 ]]; then
        echo "*** ALL UNSAT — Cube $CUBE is UNSAT ***"
    fi
    exit 0
fi

CUBE="$1"
SUBCUBE_FILE="$SATDIR/subcubes_${CUBE}.icnf"

if [[ ! -f "$SUBCUBE_FILE" ]]; then
    echo "ERROR: $SUBCUBE_FILE not found" >&2; exit 1
fi

TOTAL=$(grep -c '^a ' "$SUBCUBE_FILE")
RANGE_START="${RANGE_START:-1}"
RANGE_END="${RANGE_END:-$TOTAL}"
RESULTS="$SATDIR/subcube_results_${CUBE}"
mkdir -p "$RESULTS"

echo "Solving cube $CUBE sub-cubes $RANGE_START..$RANGE_END (of $TOTAL) with $JOBS workers"
echo "Results: $RESULTS/"
echo "Timeout per sub-cube: ${TIMEOUT}s"
echo ""

solve_one() {
    local line_num="$1"
    local result_file="$RESULTS/sc_${line_num}.result"
    local log_file="$RESULTS/sc_${line_num}.log"

    # Skip if already solved
    if [[ -f "$result_file" ]]; then
        return 0
    fi

    # Extract the sub-cube line (skip comment lines)
    local cube_line
    cube_line=$(awk '/^a /{n++; if(n=='"$line_num"') {print; exit}}' "$SUBCUBE_FILE")

    if [[ -z "$cube_line" ]]; then
        echo "SKIP" > "$result_file"
        return 0
    fi

    # Write single cube to temp file
    local tmp_cube
    tmp_cube=$(mktemp "$RESULTS/tmp_sc_${line_num}_XXXXX.icnf")
    echo "$cube_line" > "$tmp_cube"

    # Run smsg with timeout
    local t0
    t0=$(date +%s%N)
    if timeout "$TIMEOUT" "$SMSG" -v 43 --dimacs "$CNF" \
        --cube-file "$tmp_cube" --cube-line 1 > "$log_file" 2>&1; then
        local t1
        t1=$(date +%s%N)
        local elapsed=$(( (t1 - t0) / 1000000 ))

        # smsg output: "All cubes processed" = done, graph lines = SAT
        # A graph found means SAT; "All cubes processed" with no graph = UNSAT
        if grep -qP '^[A-Za-z~\?@]' "$log_file" 2>/dev/null && \
           ! grep -q '^Solve\|^Time\|^Max\|^Avg\|^Stat\|^All\|^Total\|^\t' "$log_file" 2>/dev/null; then
            # Found a graph6 line → SAT
            echo "SAT" > "$result_file"
            echo "${elapsed}ms" >> "$result_file"
            cp "$log_file" "$RESULTS/SAT_sc_${line_num}.log"
        elif grep -q 'All cubes processed' "$log_file"; then
            echo "UNSAT" > "$result_file"
            echo "${elapsed}ms" >> "$result_file"
        elif grep -q 'UNSATISFIABLE\|s UNSAT' "$log_file"; then
            echo "UNSAT" > "$result_file"
            echo "${elapsed}ms" >> "$result_file"
        elif grep -q 'SATISFIABLE\|s SAT' "$log_file"; then
            echo "SAT" > "$result_file"
            echo "${elapsed}ms" >> "$result_file"
            cp "$log_file" "$RESULTS/SAT_sc_${line_num}.log"
        else
            echo "UNKNOWN" > "$result_file"
            echo "${elapsed}ms" >> "$result_file"
        fi
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            echo "TIMEOUT" > "$result_file"
        else
            echo "ERROR" > "$result_file"
            echo "exit=$exit_code" >> "$result_file"
        fi
    fi

    rm -f "$tmp_cube"
}

export -f solve_one
export RESULTS SUBCUBE_FILE CNF SMSG TIMEOUT

# Use GNU parallel if available, otherwise xargs
if command -v parallel &>/dev/null; then
    seq "$RANGE_START" "$RANGE_END" | parallel --bar -j "$JOBS" solve_one
else
    seq "$RANGE_START" "$RANGE_END" | xargs -P "$JOBS" -I {} bash -c 'solve_one "$@"' _ {}
fi

# Summary
echo ""
echo "=== Done ==="
DONE=$(find "$RESULTS" -name 'sc_*.result' 2>/dev/null | wc -l)
UNSAT=$(grep -rl '^UNSAT$' "$RESULTS"/ 2>/dev/null | grep -c '\.result$' || true)
SAT=$(grep -rl '^SAT$' "$RESULTS"/ 2>/dev/null | grep -c '\.result$' || true)
TIMEOUT_N=$(grep -rl '^TIMEOUT$' "$RESULTS"/ 2>/dev/null | grep -c '\.result$' || true)
echo "Solved: $DONE / $TOTAL"
echo "UNSAT: $UNSAT | SAT: $SAT | TIMEOUT: $TIMEOUT_N"
