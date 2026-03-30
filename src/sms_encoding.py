#!/usr/bin/env python3
"""
SMS (SAT Modulo Symmetries) encoding for R(5,5,n).

Uses PySMS (Kirchweger-Szeider) to generate a symmetry-aware SAT instance:
  "Does there exist a graph G on n vertices such that neither G nor
   its complement contains K_5?"

This is equivalent to asking: is there a 2-coloring of K_n with no
monochromatic K_5?

SMS eliminates isomorphic solutions dynamically via the MinCheck propagator,
reducing the search space by a factor approaching n!.

Usage:
    # Check if R(5,5,n) graph exists (single answer)
    python3 sms_encoding.py --vertices 43

    # Enumerate all R(5,5,n) graphs up to isomorphism
    python3 sms_encoding.py --vertices 42 --enumerate

    # Generate DIMACS only (for external solving / BOINC)
    python3 sms_encoding.py --vertices 43 --dimacs-only --output r55_43_sms.cnf

    # Use with cube-and-conquer for BOINC
    python3 sms_encoding.py --vertices 43 --cubes --cubes-depth 20
"""

import argparse
import sys
import os
import time
from itertools import combinations

def check_pysms():
    """Check if PySMS is available."""
    try:
        from pysms.graph_builder import GraphEncodingBuilder
        return True
    except ImportError:
        return False


def build_ramsey_encoding(n, k=5):
    """
    Build the SMS encoding for R(k,k,n).

    Variables: x_{ij} for 0 <= i < j < n
      x_{ij} = 1 means edge (i,j) is in the graph (RED)
      x_{ij} = 0 means edge (i,j) is NOT in the graph (BLUE)

    Constraints:
      - No k-clique in G (no red K_k)
      - No k-independent set in G (no blue K_k)

    SMS automatically handles symmetry breaking via MinCheck.
    """
    from pysms.graph_builder import GraphEncodingBuilder

    builder = GraphEncodingBuilder(n)

    # Constraint 1: No K_k clique (no red K_5)
    # For every k-subset {v0, ..., v_{k-1}}, not all edges can be true
    print(f"Adding no-K_{k}-clique constraints...")
    clique_count = 0
    for subset in combinations(range(n), k):
        # At least one edge in the subset must be false (blue)
        edges = []
        for i in range(k):
            for j in range(i + 1, k):
                edges.append(builder.var_edge(subset[i], subset[j]))
        # Clause: OR(-e for e in edges) = not all edges are true
        builder.append([-e for e in edges])
        clique_count += 1

    # Constraint 2: No K_k independent set (no blue K_5)
    # For every k-subset, not all edges can be false
    print(f"Adding no-K_{k}-independent-set constraints...")
    indep_count = 0
    for subset in combinations(range(n), k):
        # At least one edge in the subset must be true (red)
        edges = []
        for i in range(k):
            for j in range(i + 1, k):
                edges.append(builder.var_edge(subset[i], subset[j]))
        # Clause: OR(e for e in edges) = not all edges are false
        builder.append([e for e in edges])
        indep_count += 1

    total = clique_count + indep_count
    print(f"  Clique constraints:  {clique_count}")
    print(f"  IndSet constraints:  {indep_count}")
    print(f"  Total constraints:   {total}")
    print(f"  Variables (edges):   {n*(n-1)//2}")
    print(f"  SMS symmetry group:  S_{n} (order {n}!)")

    return builder


def build_ramsey_encoding_manual(n, k=5, outfile="r55_sms.cnf"):
    """
    Build DIMACS CNF manually (when PySMS is not available).
    This produces the same clauses as our Julia sat_encoding.jl,
    but formatted for use with the smsg binary directly.
    """
    nvars = n * (n - 1) // 2

    def edge_var(i, j):
        """Map edge (i,j) with 0-indexed i < j to variable 1..C(n,2)."""
        # Convert to 1-indexed for DIMACS
        ii, jj = i + 1, j + 1
        return (ii - 1) * n - ii * (ii + 1) // 2 + jj

    clauses = []

    # No red K_k
    for subset in combinations(range(n), k):
        edges = []
        for i in range(k):
            for j in range(i + 1, k):
                edges.append(edge_var(subset[i], subset[j]))
        clauses.append([-e for e in edges])

    # No blue K_k
    for subset in combinations(range(n), k):
        edges = []
        for i in range(k):
            for j in range(i + 1, k):
                edges.append(edge_var(subset[i], subset[j]))
        clauses.append([e for e in edges])

    # Write DIMACS
    with open(outfile, "w") as f:
        f.write(f"p cnf {nvars} {len(clauses)}\n")
        for clause in clauses:
            f.write(" ".join(str(l) for l in clause) + " 0\n")

    print(f"  Written {outfile}: {nvars} vars, {len(clauses)} clauses")
    return outfile


def run_sms_solve(builder, n, enumerate_all=False):
    """
    Run SMS solver on the encoding.

    Returns list of found graphs (as adjacency info).
    """
    print(f"\n{'='*60}")
    print(f"  Running SMS solver (n={n})")
    if enumerate_all:
        print(f"  Mode: enumerate ALL graphs up to isomorphism")
    else:
        print(f"  Mode: find ONE graph (or prove UNSAT)")
    print(f"{'='*60}\n")

    start = time.time()

    if enumerate_all:
        graphs = builder.solve(all_graphs=True)
    else:
        graphs = builder.solve(all_graphs=False)

    elapsed = time.time() - start

    if graphs is None or len(graphs) == 0:
        print(f"\n  Result: UNSAT (no R({5},{5},{n}) graph exists)")
        print(f"  Time: {elapsed:.1f}s")
        if n == 43:
            print(f"\n  This confirms R(5,5) > 43 is IMPOSSIBLE")
            print(f"  (no 2-coloring of K_43 avoids monochromatic K_5)")
    else:
        print(f"\n  Result: SAT — found {len(graphs)} graph(s)")
        print(f"  Time: {elapsed:.1f}s")
        for idx, g in enumerate(graphs):
            print(f"\n  Graph {idx+1}:")
            print(f"    {g}")

    return graphs, elapsed


def run_smsg_direct(n, cnf_file, enumerate_all=False):
    """
    Run the smsg binary directly on a DIMACS file.
    This is the fallback when PySMS API doesn't work as expected.
    """
    import subprocess

    cmd = ["smsg", "-v", str(n), "--dimacs", cnf_file]
    if enumerate_all:
        cmd.append("--all-graphs")

    print(f"  Command: {' '.join(cmd)}")
    print(f"  Running...\n")

    start = time.time()
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=3600)
    elapsed = time.time() - start

    print(f"  Exit code: {result.returncode}")
    print(f"  Time: {elapsed:.1f}s")

    if result.stdout:
        # Parse output for graphs
        lines = result.stdout.strip().split("\n")
        graphs = [l for l in lines if l.startswith("Graph") or "graph6" in l.lower()]
        print(f"  Output lines: {len(lines)}")
        for line in lines[-20:]:
            print(f"    {line}")

    if result.stderr:
        err_lines = result.stderr.strip().split("\n")
        for line in err_lines[-10:]:
            print(f"  [stderr] {line}")

    return result


def main():
    parser = argparse.ArgumentParser(
        description="SMS encoding for R(5,5,n)"
    )
    parser.add_argument("--vertices", "-n", type=int, default=43,
                        help="Number of vertices (default: 43)")
    parser.add_argument("--enumerate", action="store_true",
                        help="Enumerate all graphs up to isomorphism")
    parser.add_argument("--dimacs-only", action="store_true",
                        help="Only generate DIMACS file, don't solve")
    parser.add_argument("--output", "-o", type=str, default=None,
                        help="Output file for DIMACS")
    parser.add_argument("--smsg-direct", action="store_true",
                        help="Use smsg binary directly instead of PySMS API")
    args = parser.parse_args()

    n = args.vertices
    k = 5

    print("=" * 60)
    print(f"  SMS Encoding for R({k},{k},{n})")
    print(f"  SAT Modulo Symmetries (Kirchweger-Szeider)")
    print("=" * 60)
    print(f"  Vertices:    {n}")
    print(f"  Edge vars:   {n*(n-1)//2}")
    print(f"  Subsets C({n},{k}): {len(list(combinations(range(n), k)))}")
    print(f"  Symmetry:    S_{n} (eliminates ~{n}! isomorphic copies)")
    print()

    has_pysms = check_pysms()

    if args.dimacs_only:
        # Just generate DIMACS
        outfile = args.output or f"r55_{n}_sms.cnf"
        outdir = os.path.join(os.path.dirname(__file__), "..", "results", "sat")
        os.makedirs(outdir, exist_ok=True)
        outpath = os.path.join(outdir, outfile)

        if has_pysms:
            builder = build_ramsey_encoding(n, k)
            builder.write_dimacs(outpath)
            print(f"\n  DIMACS written to {outpath}")
        else:
            build_ramsey_encoding_manual(n, k, outpath)

        print(f"\n  To solve with smsg:")
        print(f"    smsg -v {n} --dimacs {outpath}")
        if args.enumerate:
            print(f"    smsg -v {n} --dimacs {outpath} --all-graphs")
        return

    if args.smsg_direct or not has_pysms:
        # Generate DIMACS and call smsg binary
        outfile = args.output or f"r55_{n}_sms.cnf"
        outdir = os.path.join(os.path.dirname(__file__), "..", "results", "sat")
        os.makedirs(outdir, exist_ok=True)
        outpath = os.path.join(outdir, outfile)

        if has_pysms:
            builder = build_ramsey_encoding(n, k)
            builder.write_dimacs(outpath)
        else:
            print("  PySMS not found — generating DIMACS manually")
            build_ramsey_encoding_manual(n, k, outpath)

        run_smsg_direct(n, outpath, args.enumerate)
        return

    # Full PySMS workflow
    builder = build_ramsey_encoding(n, k)
    graphs, elapsed = run_sms_solve(builder, n, args.enumerate)


if __name__ == "__main__":
    main()
