#!/bin/bash
# make_cube_cnf.sh — Convert SMS cubes (iCNF format) to standalone CNF files
# Usage: ./make_cube_cnf.sh <base.cnf> <cubes.icnf> <output_dir>
#
# Input:  base CNF (DIMACS) + cubes file (lines starting with "a ... 0")
# Output: one CNF per cube: base clauses + cube assumptions as unit clauses
#         with a correct p-line header

set -euo pipefail

BASE_CNF="${1:?Usage: $0 <base.cnf> <cubes.icnf> <output_dir>}"
CUBES_FILE="${2:?Usage: $0 <base.cnf> <cubes.icnf> <output_dir>}"
OUT_DIR="${3:?Usage: $0 <base.cnf> <cubes.icnf> <output_dir>}"

mkdir -p "$OUT_DIR"

# Extract header from base CNF
NVARS=$(grep "^p cnf" "$BASE_CNF" | awk '{print $3}')

# Extract clauses only (skip comments and p-line)
BASE_CLAUSES_FILE=$(mktemp)
grep -v "^[cp]" "$BASE_CNF" | grep -v "^$" > "$BASE_CLAUSES_FILE"
BASE_NCLAUSES=$(wc -l < "$BASE_CLAUSES_FILE")

echo "Base: $NVARS vars, $BASE_NCLAUSES clauses"

CUBE_NUM=0
while IFS= read -r line; do
  CUBE_NUM=$((CUBE_NUM + 1))

  # Strip "a " prefix and trailing " 0"
  LITS=$(echo "$line" | sed 's/^a //; s/ 0$//')

  # Write unit clauses to temp file
  UNIT_FILE=$(mktemp)
  NASSUMPTIONS=0
  for lit in $LITS; do
    echo "$lit 0" >> "$UNIT_FILE"
    NASSUMPTIONS=$((NASSUMPTIONS + 1))
  done

  TOTAL=$((BASE_NCLAUSES + NASSUMPTIONS))
  OUTFILE="$OUT_DIR/cube_$(printf '%03d' $CUBE_NUM).cnf"

  # Write final CNF: header + assumptions + base clauses
  echo "p cnf $NVARS $TOTAL" > "$OUTFILE"
  cat "$UNIT_FILE" >> "$OUTFILE"
  cat "$BASE_CLAUSES_FILE" >> "$OUTFILE"
  rm "$UNIT_FILE"

  # Verify
  ACTUAL_LINES=$(($(wc -l < "$OUTFILE") - 1))
  if [ "$ACTUAL_LINES" -ne "$TOTAL" ]; then
    echo "ERROR cube $CUBE_NUM: header=$TOTAL actual=$ACTUAL_LINES" >&2
  else
    echo "Cube $CUBE_NUM: $NASSUMPTIONS assumptions, $TOTAL total clauses → $OUTFILE"
  fi

done < "$CUBES_FILE"

rm "$BASE_CLAUSES_FILE"
echo "Done: $CUBE_NUM cubes generated in $OUT_DIR"
