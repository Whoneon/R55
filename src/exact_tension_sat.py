#!/usr/bin/env python3
"""
Exact computation of extension tension τ(G) for all 656 R(5,5,42) extremal graphs.

τ(G) = min over all N ⊆ V(G) of:
    #{K₄ in G[N]} + #{I₄ in G[N̄]}

Uses SAT-based binary search with cardinality constraints (totalizer encoding).
For each candidate bound k, asks CaDiCaL: "Is there N with cost ≤ k?"
Binary search finds exact τ(G).
"""

import sys
import os
import time
import csv
from pysat.solvers import Solver
from pysat.card import CardEnc, EncType
from pysat.formula import CNF, IDPool

# ─── Graph6 reader ────────────────────────────────────────────────────────

def decode_graph6(s):
    s = s.strip()
    if s.startswith('>>graph6<<'):
        s = s[10:]
    data = [ord(c) - 63 for c in s]
    idx = 0
    if data[0] < 63:
        n = data[0]; idx = 1
    elif data[0] == 63 and data[1] < 63:
        n = (data[1] << 12) | (data[2] << 6) | data[3]; idx = 4
    else:
        n = (data[2] << 30) | (data[3] << 24) | (data[4] << 18) | \
            (data[5] << 12) | (data[6] << 6) | data[7]; idx = 8
    adj = [set() for _ in range(n)]
    bits = []
    for d in data[idx:]:
        for k in range(5, -1, -1):
            bits.append((d >> k) & 1)
    bit_idx = 0
    for j in range(1, n):
        for i in range(j):
            if bit_idx < len(bits) and bits[bit_idx]:
                adj[i].add(j); adj[j].add(i)
            bit_idx += 1
    return n, adj

def complement_graph(n, adj):
    cadj = [set() for _ in range(n)]
    for i in range(n):
        for j in range(i + 1, n):
            if j not in adj[i]:
                cadj[i].add(j); cadj[j].add(i)
    return cadj

# ─── K₄ enumeration ──────────────────────────────────────────────────────

def enumerate_K4(n, adj):
    cliques = []
    for i in range(n):
        ni = adj[i]
        for j in ni:
            if j <= i: continue
            nij = ni & adj[j]
            for k in nij:
                if k <= j: continue
                nijk = nij & adj[k]
                for l in nijk:
                    if l <= k: continue
                    cliques.append((i, j, k, l))
    return cliques

# ─── SAT encoding ────────────────────────────────────────────────────────

def exact_tension_sat(n, adj, initial_ub=None):
    """
    Compute exact τ(G) using SAT + binary search + cardinality constraints.

    Encoding:
      - x[i] for i in 0..n-1: vertex i ∈ N (SAT var i+1)
      - v[k] for each K₄: violation indicator (v[k]=True iff K₄ is fully "hit")
      - Reification: v[k] ↔ AND(...)
      - Cardinality: sum(v[k]) ≤ bound (totalizer encoding)

    Binary search on bound to find minimum τ.
    """
    cadj = complement_graph(n, adj)
    red_cliques = enumerate_K4(n, adj)
    blue_cliques = enumerate_K4(n, cadj)

    total_cliques = len(red_cliques) + len(blue_cliques)

    # Variable allocation
    pool = IDPool(start_from=1)
    x_vars = [pool.id(('x', i)) for i in range(n)]  # x[i]: vertex i in N

    # Violation variables
    v_vars = []
    base_clauses = []

    # Red K₄ (a,b,c,d): violated iff all in N → v ↔ (x[a] ∧ x[b] ∧ x[c] ∧ x[d])
    for idx, (a, b, c, d) in enumerate(red_cliques):
        v = pool.id(('vr', idx))
        v_vars.append(v)
        xa, xb, xc, xd = x_vars[a], x_vars[b], x_vars[c], x_vars[d]
        # v → x[a], v → x[b], v → x[c], v → x[d]
        base_clauses.append([-v, xa])
        base_clauses.append([-v, xb])
        base_clauses.append([-v, xc])
        base_clauses.append([-v, xd])
        # x[a] ∧ x[b] ∧ x[c] ∧ x[d] → v
        base_clauses.append([v, -xa, -xb, -xc, -xd])

    # Blue I₄ (a,b,c,d): violated iff all in N̄ → v ↔ (¬x[a] ∧ ¬x[b] ∧ ¬x[c] ∧ ¬x[d])
    for idx, (a, b, c, d) in enumerate(blue_cliques):
        v = pool.id(('vb', idx))
        v_vars.append(v)
        xa, xb, xc, xd = x_vars[a], x_vars[b], x_vars[c], x_vars[d]
        # v → ¬x[a], v → ¬x[b], v → ¬x[c], v → ¬x[d]
        base_clauses.append([-v, -xa])
        base_clauses.append([-v, -xb])
        base_clauses.append([-v, -xc])
        base_clauses.append([-v, -xd])
        # ¬x[a] ∧ ¬x[b] ∧ ¬x[c] ∧ ¬x[d] → v
        base_clauses.append([v, xa, xb, xc, xd])

    # Get initial upper bound from heuristic or caller
    if initial_ub is None:
        initial_ub = total_cliques  # worst case

    # Heuristic: try random assignments to get a good upper bound
    # Use bitmask operations for speed
    import random
    vmask = (1 << n) - 1
    # Pre-convert cliques to bitmasks for fast evaluation
    red_masks = [(1 << a) | (1 << b) | (1 << c) | (1 << d) for (a,b,c,d) in red_cliques]
    blue_masks = [(1 << a) | (1 << b) | (1 << c) | (1 << d) for (a,b,c,d) in blue_cliques]

    best_heur = initial_ub
    for _ in range(100_000):
        m = random.getrandbits(n) & vmask
        am = vmask & ~m
        cost = sum(1 for rm in red_masks if (rm & m) == rm) + \
               sum(1 for bm in blue_masks if (bm & am) == bm)
        if cost < best_heur:
            best_heur = cost
    ub = best_heur

    # Binary search: find minimum k such that "sum(v) ≤ k" is SAT
    # Start from ub and work down
    lo, hi = 0, ub
    best_model = None

    t0 = time.time()

    while lo < hi:
        mid = (lo + hi) // 2

        # Build cardinality constraint: sum(v_vars) ≤ mid
        # Using totalizer encoding (most efficient for incremental)
        card_clauses = CardEnc.atmost(
            lits=v_vars, bound=mid,
            top_id=pool.top, encoding=EncType.totalizer
        )

        # Create solver with all clauses
        with Solver(name='cd195') as sat:
            for cl in base_clauses:
                sat.add_clause(cl)
            for cl in card_clauses.clauses:
                sat.add_clause(cl)

            result = sat.solve()
            if result:
                # SAT: τ ≤ mid, extract model
                model = sat.get_model()
                best_model = model
                hi = mid
            else:
                # UNSAT: τ > mid
                lo = mid + 1

    elapsed = time.time() - t0
    tau = lo  # = hi = exact τ

    # Extract mask from best model
    mask = 0
    if best_model:
        model_set = set(best_model)
        for i in range(n):
            if x_vars[i] in model_set:
                mask |= (1 << i)

    degree = bin(mask).count('1')
    return tau, mask, degree, elapsed, ub


def main():
    datafile = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            '..', 'data', 'r55_42some.g6')
    if not os.path.isfile(datafile):
        print(f"ERROR: {datafile} not found"); sys.exit(1)

    with open(datafile) as f:
        lines = [l.strip() for l in f if l.strip()]
    print(f"Loaded {len(lines)} base graphs")

    outfile = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           '..', 'results', 'exact_tension.csv')
    os.makedirs(os.path.dirname(outfile), exist_ok=True)

    # Resume support
    existing = {}
    if os.path.isfile(outfile):
        with open(outfile) as f:
            reader = csv.DictReader(f)
            for row in reader:
                if row.get('optimal') == 'True':
                    existing[int(row['graph_idx'])] = int(row['tau'])

    mode = 'a' if existing else 'w'

    with open(outfile, mode, newline='') as csvf:
        writer = csv.writer(csvf)
        if not existing:
            writer.writerow(['graph_idx', 'is_complement', 'base_idx', 'tau',
                             'best_mask_hex', 'degree_new_vertex', 'optimal',
                             'time_s'])

        for i, line in enumerate(lines):
            n, adj = decode_graph6(line)
            cadj = complement_graph(n, adj)

            for j, (gadj, is_comp) in enumerate([(adj, False), (cadj, True)]):
                gidx = 2 * i + j + 1
                if gidx in existing:
                    continue

                label = "comp" if is_comp else "orig"

                tau, mask, deg, elapsed, heur = exact_tension_sat(n, gadj)

                print(f"Graph {gidx:3d}/656 (base {i+1:3d}, {label}): "
                      f"τ = {tau:3d} (heur={heur:3d}), deg = {deg:2d}, "
                      f"{elapsed:.1f}s")

                writer.writerow([gidx, is_comp, i + 1, tau,
                                 f'{mask:011x}', deg, True, f'{elapsed:.1f}'])
                csvf.flush()

    # Summary
    all_taus = []
    with open(outfile) as f:
        reader = csv.DictReader(f)
        for row in reader:
            all_taus.append(int(row['tau']))

    if all_taus:
        print(f"\n{'=' * 60}")
        print(f"SUMMARY: {len(all_taus)} graphs")
        print(f"{'=' * 60}")
        print(f"  min τ = {min(all_taus)}")
        print(f"  max τ = {max(all_taus)}")
        print(f"  mean τ = {sum(all_taus) / len(all_taus):.2f}")
        sorted_taus = sorted(all_taus)
        mid = len(sorted_taus) // 2
        if len(sorted_taus) % 2 == 0 and len(sorted_taus) >= 2:
            median = (sorted_taus[mid - 1] + sorted_taus[mid]) / 2
        else:
            median = sorted_taus[mid]
        print(f"  median τ = {median:.1f}")

        from collections import Counter
        dist = Counter(all_taus)
        print("\nDistribution:")
        for tv in sorted(dist):
            c = dist[tv]
            print(f"  τ = {tv:3d}: {c:3d} ({100*c/len(all_taus):.1f}%)")

    print(f"\nResults: {outfile}")


if __name__ == '__main__':
    main()
