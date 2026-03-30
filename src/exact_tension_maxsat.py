#!/usr/bin/env python3
"""
Exact computation of extension tension τ(G) for all 656 R(5,5,42) extremal graphs.

τ(G) = min over all N ⊆ V(G) of:
    #{K₄ in G[N]} + #{I₄ in G[N̄]}

Uses PySAT RC2 (MaxSAT solver) for proven-optimal binary optimization.

Encoding as partial weighted MaxSAT:
  - Hard clauses: none (all assignments are feasible)
  - Soft clauses (weight 1 each):
    - For each red K₄ (a,b,c,d): soft clause (¬x[a] ∨ ¬x[b] ∨ ¬x[c] ∨ ¬x[d])
      "at least one vertex NOT in N" — violated iff all 4 are in N (= red K₅)
    - For each blue I₄ (a,b,c,d): soft clause (x[a] ∨ x[b] ∨ x[c] ∨ x[d])
      "at least one vertex IN N" — violated iff all 4 are in N̄ (= blue K₅)

  MaxSAT maximizes satisfied soft clauses = (n_red + n_blue) - τ(G).
  So τ(G) = (n_red + n_blue) - optimal_value.
"""

import sys
import os
import time
import csv
from pysat.examples.rc2 import RC2
from pysat.formula import WCNF

# ─── Graph6 reader ────────────────────────────────────────────────────────

def decode_graph6(s):
    s = s.strip()
    if s.startswith('>>graph6<<'):
        s = s[10:]

    data = [ord(c) - 63 for c in s]
    idx = 0

    if data[0] < 63:
        n = data[0]
        idx = 1
    elif data[0] == 63 and data[1] < 63:
        n = (data[1] << 12) | (data[2] << 6) | data[3]
        idx = 4
    else:
        n = (data[2] << 30) | (data[3] << 24) | (data[4] << 18) | \
            (data[5] << 12) | (data[6] << 6) | data[7]
        idx = 8

    adj = [set() for _ in range(n)]
    bits = []
    for d in data[idx:]:
        for k in range(5, -1, -1):
            bits.append((d >> k) & 1)

    bit_idx = 0
    for j in range(1, n):
        for i in range(j):
            if bit_idx < len(bits) and bits[bit_idx]:
                adj[i].add(j)
                adj[j].add(i)
            bit_idx += 1

    return n, adj


def complement_graph(n, adj):
    cadj = [set() for _ in range(n)]
    for i in range(n):
        for j in range(i + 1, n):
            if j not in adj[i]:
                cadj[i].add(j)
                cadj[j].add(i)
    return cadj


# ─── K₄ enumeration ──────────────────────────────────────────────────────

def enumerate_K4(n, adj):
    cliques = []
    for i in range(n):
        ni = adj[i]
        for j in ni:
            if j <= i:
                continue
            nij = ni & adj[j]
            for k in nij:
                if k <= j:
                    continue
                nijk = nij & adj[k]
                for l in nijk:
                    if l <= k:
                        continue
                    cliques.append((i, j, k, l))
    return cliques


# ─── MaxSAT formulation ──────────────────────────────────────────────────

def exact_tension_maxsat(n, adj):
    """
    Compute exact τ(G) using RC2 MaxSAT solver.

    Variables: x[1..n] (1-indexed for DIMACS), x[i]=True iff vertex i-1 ∈ N.

    Returns: (τ, mask, degree, solve_time)
    All results are proven optimal (RC2 is exact).
    """
    cadj = complement_graph(n, adj)
    red_cliques = enumerate_K4(n, adj)
    blue_cliques = enumerate_K4(n, cadj)

    n_red = len(red_cliques)
    n_blue = len(blue_cliques)

    wcnf = WCNF()

    # Soft clauses for red K₄s:
    # "avoid red K₅" = at least one of {a,b,c,d} not in N
    # clause: (¬x[a+1] ∨ ¬x[b+1] ∨ ¬x[c+1] ∨ ¬x[d+1]), weight 1
    for (a, b, c, d) in red_cliques:
        wcnf.append([-(a+1), -(b+1), -(c+1), -(d+1)], weight=1)

    # Soft clauses for blue I₄s:
    # "avoid blue K₅" = at least one of {a,b,c,d} in N
    # clause: (x[a+1] ∨ x[b+1] ∨ x[c+1] ∨ x[d+1]), weight 1
    for (a, b, c, d) in blue_cliques:
        wcnf.append([(a+1), (b+1), (c+1), (d+1)], weight=1)

    t0 = time.time()
    with RC2(wcnf) as solver:
        model = solver.compute()
        cost = solver.cost  # number of violated soft clauses = τ(G)
    elapsed = time.time() - t0

    if model is None:
        return -1, 0, 0, elapsed

    # Extract neighbor set from model
    mask = 0
    for lit in model:
        if lit > 0 and lit <= n:
            mask |= (1 << (lit - 1))

    degree = bin(mask).count('1')
    return cost, mask, degree, elapsed


# ─── Main ─────────────────────────────────────────────────────────────────

def main():
    datafile = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            '..', 'data', 'r55_42some.g6')
    if not os.path.isfile(datafile):
        print(f"ERROR: {datafile} not found")
        sys.exit(1)

    with open(datafile) as f:
        lines = [l.strip() for l in f if l.strip()]

    print(f"Loaded {len(lines)} base graphs")

    outfile = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           '..', 'results', 'exact_tension.csv')
    os.makedirs(os.path.dirname(outfile), exist_ok=True)

    # Resume: skip already-computed optimal results
    existing = set()
    if os.path.isfile(outfile):
        with open(outfile) as f:
            reader = csv.DictReader(f)
            for row in reader:
                existing.add(int(row['graph_idx']))

    mode = 'a' if existing else 'w'
    all_taus = []

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

                tau, mask, deg, elapsed = exact_tension_maxsat(n, gadj)
                all_taus.append(tau)

                print(f"Graph {gidx:3d}/656 (base {i+1:3d}, {label}): "
                      f"τ = {tau:3d}, deg = {deg:2d} ({elapsed:.1f}s)")

                writer.writerow([gidx, is_comp, i + 1, tau,
                                 f'{mask:011x}', deg, True, f'{elapsed:.1f}'])
                csvf.flush()

    # Re-read all results for summary
    all_taus = []
    with open(outfile) as f:
        reader = csv.DictReader(f)
        for row in reader:
            all_taus.append(int(row['tau']))

    if all_taus:
        print(f"\n{'=' * 60}")
        print(f"SUMMARY: {len(all_taus)} graphs computed")
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
        for tau_val in sorted(dist):
            cnt = dist[tau_val]
            print(f"  τ = {tau_val:3d}: {cnt:3d} graphs "
                  f"({100.0 * cnt / len(all_taus):.1f}%)")

    print(f"\nResults: {outfile}")


if __name__ == '__main__':
    main()
