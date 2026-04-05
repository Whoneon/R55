#!/usr/bin/env bash
#
# Generate commands to distribute sub-cube solving across machines.
#
# Usage:
#   ./distribute_subcubes.sh <cube> <n_machines> [remote_dir]
#
# Example (2 machines):
#   ./distribute_subcubes.sh 3 2 /home/antoh/R55
#
# Output: prints the commands to run on each machine.
# Prerequisites on each machine: smsg, the CNF file, and the subcubes file.
#
set -euo pipefail

CUBE="${1:?Usage: $0 <cube> <n_machines> [remote_dir]}"
N_MACHINES="${2:?Usage: $0 <cube> <n_machines> [remote_dir]}"
REMOTE_DIR="${3:-/home/antoh/Desktop/R55}"
SATDIR="$(cd "$(dirname "$0")/../results/sat" && pwd)"

TOTAL=$(grep -c '^a ' "$SATDIR/subcubes_${CUBE}.icnf")
PER_MACHINE=$(( (TOTAL + N_MACHINES - 1) / N_MACHINES ))

echo "=== Cube $CUBE: $TOTAL sub-cubes, $N_MACHINES machines, ~$PER_MACHINE each ==="
echo ""
echo "# Files needed on each machine:"
echo "#   $REMOTE_DIR/results/sat/r55_43_sms.cnf"
echo "#   $REMOTE_DIR/results/sat/subcubes_${CUBE}.icnf"
echo "#   $REMOTE_DIR/src/solve_subcubes.sh"
echo ""
echo "# To copy files to a remote machine:"
echo "#   rsync -avz results/sat/r55_43_sms.cnf results/sat/subcubes_${CUBE}.icnf src/solve_subcubes.sh user@host:$REMOTE_DIR/"
echo ""

for i in $(seq 1 "$N_MACHINES"); do
    START=$(( (i - 1) * PER_MACHINE + 1 ))
    END=$(( i * PER_MACHINE ))
    if [[ $END -gt $TOTAL ]]; then END=$TOTAL; fi
    echo "# Machine $i (sub-cubes $START..$END):"
    echo "cd $REMOTE_DIR && RANGE_START=$START RANGE_END=$END ./src/solve_subcubes.sh $CUBE"
    echo ""
done

echo "# After all machines finish, collect results into one directory and run:"
echo "# ./src/solve_subcubes.sh --check $CUBE"
